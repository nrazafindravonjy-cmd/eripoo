import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/ids/ids.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/log_value.dart';
import '../../core/time/clock.dart';
import '../../data/local/app_database.dart';
import '../../data/local/entity_types.dart';
import '../../security/crypto_service.dart';
import '../../security/envelopes.dart';
import '../remote/sync_remote.dart';
import 'conflict_resolution.dart';
import 'entity_registry.dart';

enum SyncLog implements LogEventCode {
  cycleFinished,
  pushRejected,
  undecryptableRecord,
  unknownSchema,
  remoteUnavailable,
}

/// What a sync cycle achieved.
class SyncReport {
  const SyncReport({
    required this.pushed,
    required this.pulled,
    required this.conflicts,
    required this.complete,
    required this.pendingLeft,
  });

  final int pushed;
  final int pulled;
  final int conflicts;

  /// Local changes still waiting to be sent after this cycle (including
  /// changes the server refused, kept locally for a later retry).
  final int pendingLeft;

  /// True only if the cycle ran to the end **and** nothing is left to send:
  /// the only state in which the app may say "saved".
  final bool complete;
}

/// Identity and keys needed to synchronise.
class SyncSession {
  const SyncSession({
    required this.ownerId,
    required this.deviceId,
    required this.recordKey,
    required this.umkVersion,
  });

  final String ownerId;
  final String deviceId;
  final SecureKey recordKey;
  final int umkVersion;
}

/// Pull → push cycle (docs/OFFLINE_SYNC.md §4–8).
///
/// Guarantees:
/// * a local change is cleared only once the server confirmed **that**
///   change (`change_id`), so edits made during a push are never lost;
/// * a pulled page and the cursor are committed in one transaction;
/// * our own change coming back (response lost after the server applied
///   it) is recognised with `pushed_change_id`, not treated as a conflict;
/// * a conflict never drops a version: the one not kept becomes a
///   conflict copy, itself synchronised.
class SyncEngine {
  SyncEngine({
    required this._db,
    required this._remote,
    required CryptoService crypto,
    required this._logger,
    this._clock = systemClock,
    this.batchSize = 50,
    this.pullPageSize = 200,
    this.appSchemaVersion = EntityRegistry.schemaVersion,
  }) : _registry = EntityRegistry(_db),
       _envelopes = RecordEnvelopes(crypto);

  final AppDatabase _db;
  final SyncRemote _remote;
  final AppLogger _logger;
  final Clock _clock;
  final EntityRegistry _registry;
  final RecordEnvelopes _envelopes;
  final int batchSize;
  final int pullPageSize;

  /// The payload format this app reads ([EntityRegistry.schemaVersion];
  /// tests simulate an updated app).
  final int appSchemaVersion;

  static const _cursorKey = 'sync.cursor';

  /// Records skipped because a newer app wrote them: the lowest server
  /// version skipped, and the format this app read then. After an update,
  /// the pull starts again from there (scenario 12).
  static const _replayFromKey = 'sync.replay_from';
  static const _replaySchemaKey = 'sync.replay_schema';
  static const _registeredKey = 'sync.device_registered';

  int _now() => _clock().millisecondsSinceEpoch;

  /// Runs one cycle. Throws [DeviceRevoked] (caller must wipe local data)
  /// and [NotAuthenticated] (caller must ask to sign in again); network
  /// failures end the cycle early and are retried later.
  Future<SyncReport> runCycle(SyncSession session) async {
    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    try {
      await _ensureRegistered(session);
      await _replayAfterUpdate();
      // Pull first: if a previous push was applied but its response lost,
      // the change comes back here and is recognised as ours before any
      // new push overwrites what is in flight. Then push; if the push met
      // conflicts, their resolution is pushed in a second round.
      for (var round = 0; round < 3; round++) {
        final pull = await _pullAll(session);
        pulled += pull.$1;
        conflicts += pull.$2;
        final push = await _pushAll(session);
        pushed += push.$1;
        conflicts += push.$2;
        if (push.$2 == 0) break;
      }
    } on RemoteUnavailable {
      _logger.warning(SyncLog.remoteUnavailable);
      return SyncReport(
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        complete: false,
        pendingLeft: await _pendingCount(),
      );
    }
    final pendingLeft = await _pendingCount();
    _logger.info(SyncLog.cycleFinished, {
      'pushed': LogInt(pushed),
      'pulled': LogInt(pulled),
      'conflicts': LogInt(conflicts),
      'pendingLeft': LogInt(pendingLeft),
    });
    return SyncReport(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      complete: pendingLeft == 0,
      pendingLeft: pendingLeft,
    );
  }

  /// The app was updated since records were skipped as too new: move the
  /// cursor back so they are pulled again. Records already applied are
  /// recognised by their version and skipped.
  Future<void> _replayAfterUpdate() async {
    final from = int.tryParse(await _db.readValue(_replayFromKey) ?? '');
    final schema = int.tryParse(await _db.readValue(_replaySchemaKey) ?? '');
    if (from == null || schema == null || appSchemaVersion <= schema) return;
    await _db.transaction(() async {
      final cursor = int.tryParse(await _db.readValue(_cursorKey) ?? '') ?? 0;
      if (from - 1 < cursor) {
        await _db.writeValue(_cursorKey, '${from - 1}');
      }
      await _db.deleteValue(_replayFromKey);
      await _db.deleteValue(_replaySchemaKey);
    });
  }

  Future<void> _rememberSkipped(RemoteRecord record) async {
    final from = int.tryParse(await _db.readValue(_replayFromKey) ?? '');
    if (from == null || record.version < from) {
      await _db.writeValue(_replayFromKey, '${record.version}');
    }
    await _db.writeValue(_replaySchemaKey, '$appSchemaVersion');
  }

  Future<int> _pendingCount() async {
    final count = _db.syncMetaEntries.entityId.count(
      filter: _db.syncMetaEntries.changeId.isNotNull(),
    );
    final row = await (_db.selectOnly(
      _db.syncMetaEntries,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> _ensureRegistered(SyncSession session) async {
    if (await _db.readValue(_registeredKey) == session.deviceId) return;
    await _remote.registerDevice(session.deviceId, 'Eripoo');
    await _db.writeValue(_registeredKey, session.deviceId);
  }

  // ------------------------------------------------------------------ push

  Future<(int, int)> _pushAll(SyncSession session) async {
    var pushed = 0;
    var conflicts = 0;
    for (var guard = 0; guard < 1000; guard++) {
      final batch = await _pendingBatch();
      if (batch.isEmpty) break;
      final result = await _pushBatch(session, batch);
      pushed += result.$1;
      conflicts += result.$2;
      if (result.$1 == 0 && result.$2 == 0) break; // only rejections left
    }
    return (pushed, conflicts);
  }

  Future<List<SyncMetaRow>> _pendingBatch() {
    final now = _now();
    return (_db.select(_db.syncMetaEntries)
          ..where(
            (t) =>
                t.changeId.isNotNull() &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..limit(batchSize))
        .get()
        .then(
          (rows) => rows
            ..sort(
              (a, b) => EntityTypes.all
                  .indexOf(a.entityType)
                  .compareTo(EntityTypes.all.indexOf(b.entityType)),
            ),
        );
  }

  Future<(int, int)> _pushBatch(
    SyncSession session,
    List<SyncMetaRow> batch,
  ) async {
    final puts = <RemotePut>[];
    final sent = <String, SyncMetaRow>{};
    for (final meta in batch) {
      if (meta.purgeRequested) {
        // Tombstone: no content leaves the phone.
        puts.add(
          RemotePut(
            id: meta.entityId,
            changeId: meta.changeId!,
            baseVersion: meta.baseVersion,
            deleted: true,
            umkVersion: session.umkVersion,
            payload: null,
          ),
        );
        sent[meta.entityId] = meta;
        continue;
      }
      final json = await _registry.read(meta.entityType, meta.entityId);
      if (json == null) {
        // Nothing to send (row purged locally): clear the mark.
        await _clearChange(meta, meta.changeId!);
        continue;
      }
      puts.add(
        RemotePut(
          id: meta.entityId,
          changeId: meta.changeId!,
          baseVersion: meta.baseVersion,
          deleted: json['deletedAt'] != null,
          umkVersion: session.umkVersion,
          payload: _seal(session, meta.entityType, meta.entityId, json),
        ),
      );
      sent[meta.entityId] = meta;
    }
    if (puts.isEmpty) return (0, 0);

    // Remember what is in flight before sending: if the response is lost,
    // the change coming back from the server is recognised as ours.
    await _db.transaction(() async {
      for (final meta in sent.values) {
        await _updateMeta(
          meta,
          SyncMetaEntriesCompanion(pushedChangeId: Value(meta.changeId)),
        );
      }
    });

    final List<PushResult> results;
    try {
      results = await _remote.push(session.deviceId, puts);
    } on RemoteUnavailable {
      // The whole request failed (network): nothing is entry-specific, so
      // the batch stays pending and is sent again at the next cycle. Retry
      // pacing belongs to the caller, never to individual changes (a
      // per-change delay made later cycles skip them and report "complete").
      rethrow;
    } on DeviceUnknown {
      await _db.writeValue(_registeredKey, '');
      await _ensureRegistered(session);
      return (0, 0);
    } on RemoteRejected {
      await _markRejected(sent.values, 'batch_rejected');
      return (0, 0);
    }

    var applied = 0;
    var conflicts = 0;
    for (final result in results) {
      final meta = sent[result.id];
      if (meta == null) continue;
      switch (result) {
        case PushApplied(:final version) when meta.purgeRequested:
          await _confirmPurge(meta, version);
          applied++;
        case PushApplied(:final version):
          await _clearChange(meta, meta.changeId!, version: version);
          applied++;
        case PushConflict(:final current) when meta.purgeRequested:
          // Changed elsewhere meanwhile (restored or edited on another
          // phone): the purge is cancelled, the other version kept.
          await _db.transaction(() async {
            await _updateMeta(
              meta,
              const SyncMetaEntriesCompanion(
                purgeRequested: Value(false),
                changeId: Value(null),
                baseVersion: Value(null),
              ),
            );
            if (current != null) {
              await _applyRemote(session, current, knownType: meta.entityType);
            }
          });
          conflicts++;
        case PushConflict(:final current):
          await _db.transaction(() async {
            if (current == null) {
              // The server has no such record: send it again as new.
              await _updateMeta(
                meta,
                const SyncMetaEntriesCompanion(baseVersion: Value(null)),
              );
            } else {
              await _applyRemote(session, current, knownType: meta.entityType);
            }
          });
          conflicts++;
        case PushRejected(:final reason):
          _logger.warning(SyncLog.pushRejected);
          await _markRejected([meta], reason);
      }
    }
    return (applied, conflicts);
  }

  Uint8List _seal(
    SyncSession session,
    String entityType,
    String id,
    Map<String, Object?> json,
  ) => _envelopes.seal(
    plaintext: Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          't': entityType,
          's': EntityRegistry.schemaVersion,
          'd': json,
        }),
      ),
    ),
    recordKey: session.recordKey,
    umkVersion: session.umkVersion,
    ownerId: session.ownerId,
    recordId: id,
  );

  /// Clears the pending mark only if no newer local change happened
  /// meanwhile; always records the server version as the new base.
  Future<void> _clearChange(
    SyncMetaRow meta,
    String sentChangeId, {
    int? version,
  }) => _db.transaction(() async {
    final current = await _meta(meta.entityType, meta.entityId);
    if (current == null) return;
    await _updateMeta(
      current,
      SyncMetaEntriesCompanion(
        baseVersion: version == null ? const Value.absent() : Value(version),
        changeId: current.changeId == sentChangeId
            ? const Value(null)
            : const Value.absent(),
        lastError: const Value(null),
        attempts: const Value(0),
        nextAttemptAt: const Value(null),
      ),
    );
  });

  /// The server keeps the tombstone: the row can go. A change made here
  /// after asking (a restore) cancels nothing already sent and is kept.
  Future<void> _confirmPurge(SyncMetaRow meta, int version) =>
      _db.transaction(() async {
        final current = await _meta(meta.entityType, meta.entityId);
        if (current == null) return;
        if (current.changeId == meta.changeId) {
          await _registry.delete(meta.entityType, meta.entityId);
        }
        await _updateMeta(
          current,
          SyncMetaEntriesCompanion(
            baseVersion: Value(version),
            purgeRequested: const Value(false),
            changeId: current.changeId == meta.changeId
                ? const Value(null)
                : const Value.absent(),
            lastError: const Value(null),
            attempts: const Value(0),
            nextAttemptAt: const Value(null),
          ),
        );
      });

  Future<void> _markRejected(Iterable<SyncMetaRow> metas, String reason) =>
      _db.transaction(() async {
        for (final meta in metas) {
          await _updateMeta(
            meta,
            SyncMetaEntriesCompanion(
              lastError: Value(reason),
              attempts: Value(meta.attempts + 1),
              // Kept locally; retried after a long delay or a new edit.
              nextAttemptAt: Value(
                _now() + const Duration(hours: 1).inMilliseconds,
              ),
            ),
          );
        }
      });

  // ------------------------------------------------------------------ pull

  Future<(int, int)> _pullAll(SyncSession session) async {
    var pulled = 0;
    var conflicts = 0;
    for (var guard = 0; guard < 10000; guard++) {
      final since = int.tryParse(await _db.readValue(_cursorKey) ?? '') ?? 0;
      final page = await _remote.pull(
        session.deviceId,
        since,
        limit: pullPageSize,
      );
      if (page.records.isEmpty) break;
      // The page and the cursor are committed together, or not at all.
      await _db.transaction(() async {
        for (final record in page.records) {
          if (await _applyRemote(session, record)) conflicts++;
          pulled++;
        }
        await _db.writeValue(_cursorKey, '${page.records.last.version}');
      });
      if (page.records.last.version >= page.head) break;
    }
    return (pulled, conflicts);
  }

  /// Applies one remote record. Returns true if it was a conflict.
  Future<bool> _applyRemote(
    SyncSession session,
    RemoteRecord record, {
    String? knownType,
  }) async {
    if (record.payload == null) {
      return _applyPurge(record);
    }

    final Map<String, Object?> envelope;
    try {
      final plain = _envelopes.open(
        envelope: record.payload!,
        recordKey: session.recordKey,
        ownerId: session.ownerId,
        recordId: record.id,
      );
      envelope = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
    } on DecryptionFailed {
      // Wrong key (another key version) or tampered data: the record stays
      // on the server, untouched; counted, never logged with content.
      _logger.warning(SyncLog.undecryptableRecord);
      return false;
    }
    final type = envelope['t']! as String;
    if ((envelope['s']! as int) > appSchemaVersion ||
        !_registry.supports(type)) {
      // Written by a newer app version: not overwritten, kept on the
      // server; pulled again and applied after an update.
      _logger.warning(SyncLog.unknownSchema);
      await _rememberSkipped(record);
      return false;
    }
    final remote = Map<String, Object?>.from(envelope['d']! as Map);
    final meta = await _meta(type, record.id);

    if (meta?.baseVersion != null && record.version <= meta!.baseVersion!) {
      return false; // already known
    }

    if (meta == null || meta.changeId == null) {
      await _registry.write(type, remote);
      await _setBase(type, record.id, record.version);
      return false;
    }

    if (record.changeId == meta.pushedChangeId) {
      // Our own change came back (response lost after the server applied
      // it): not a conflict.
      await _updateMeta(
        meta,
        SyncMetaEntriesCompanion(
          baseVersion: Value(record.version),
          changeId: meta.changeId == meta.pushedChangeId
              ? const Value(null)
              : const Value.absent(),
        ),
      );
      return false;
    }

    if (meta.purgeRequested) {
      // Deleted forever here, changed (restored, edited) on another phone
      // meanwhile: the other version wins, nothing is lost; the purge is
      // cancelled (docs/OFFLINE_SYNC.md §7).
      await _registry.write(type, remote);
      await _updateMeta(
        meta,
        SyncMetaEntriesCompanion(
          baseVersion: Value(record.version),
          changeId: const Value(null),
          purgeRequested: const Value(false),
        ),
      );
      return true;
    }

    final local = await _registry.read(type, record.id);
    if (local == null) {
      await _registry.write(type, remote);
      await _setBase(type, record.id, record.version);
      return false;
    }
    final outcome = resolveConflict(
      entityType: type,
      local: local,
      remote: remote,
    );
    await _registry.write(type, outcome.merged);
    await _updateMeta(
      meta,
      SyncMetaEntriesCompanion(
        baseVersion: Value(record.version),
        changeId: Value(Ids.random()),
      ),
    );
    final aside = outcome.setAside;
    if (aside != null) {
      await _saveConflictCopy(type, record.id, aside, record.deviceId);
    }
    return true;
  }

  Future<bool> _applyPurge(RemoteRecord record) async {
    final metas = await (_db.select(
      _db.syncMetaEntries,
    )..where((t) => t.entityId.equals(record.id))).get();
    for (final meta in metas) {
      if (meta.changeId != null) {
        // Edited here after the purge elsewhere: keep it, send it as new.
        await _updateMeta(
          meta,
          const SyncMetaEntriesCompanion(baseVersion: Value(null)),
        );
        return true;
      }
      await _registry.delete(meta.entityType, meta.entityId);
      await _setBase(meta.entityType, meta.entityId, record.version);
    }
    return false;
  }

  Future<void> _saveConflictCopy(
    String entityType,
    String entityId,
    Map<String, Object?> payload,
    String fromDeviceId,
  ) async {
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.conflictCopies)
        .insert(
          ConflictCopiesCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            payloadJson: jsonEncode(payload),
            fromDeviceId: Value(fromDeviceId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _db
        .into(_db.syncMetaEntries)
        .insert(
          SyncMetaEntriesCompanion.insert(
            entityType: EntityTypes.conflictCopy,
            entityId: id,
            changeId: Value(Ids.random()),
          ),
        );
  }

  // --------------------------------------------------------------- helpers

  Future<SyncMetaRow?> _meta(String type, String id) =>
      (_db.select(_db.syncMetaEntries)
            ..where((t) => t.entityType.equals(type) & t.entityId.equals(id)))
          .getSingleOrNull();

  Future<void> _updateMeta(
    SyncMetaRow meta,
    SyncMetaEntriesCompanion changes,
  ) =>
      (_db.update(_db.syncMetaEntries)..where(
            (t) =>
                t.entityType.equals(meta.entityType) &
                t.entityId.equals(meta.entityId),
          ))
          .write(changes);

  Future<void> _setBase(String type, String id, int version) => _db
      .into(_db.syncMetaEntries)
      .insertOnConflictUpdate(
        SyncMetaEntriesCompanion.insert(
          entityType: type,
          entityId: id,
          baseVersion: Value(version),
          changeId: const Value(null),
          pushedChangeId: const Value(null),
          lastError: const Value(null),
          attempts: const Value(0),
          nextAttemptAt: const Value(null),
        ),
      );
}
