import 'package:drift/drift.dart';

import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../../../sync/engine/entity_registry.dart';
import '../../media/application/media_sync.dart';
import '../../media/data/media_store.dart';

/// What the user can delete and find again in the trash.
enum TrashKind { observation, interview, evidence, competitor }

/// One element in the trash. [label] is the user's own text: shown on
/// screen only, never logged.
class TrashItem {
  const TrashItem({
    required this.kind,
    required this.id,
    required this.label,
    required this.deletedAt,
    required this.purgeAt,
    this.mediaId,
    this.amountMga,
  });

  final TrashKind kind;
  final String id;
  final String label;
  final DateTime deletedAt;

  /// When it is deleted forever by itself.
  final DateTime purgeAt;

  /// The photo deleted with an evidence (restored or purged with it).
  final String? mediaId;
  final int? amountMga;
}

/// The trash (docs/OFFLINE_SYNC.md §7): deleting moves an element there on
/// every phone of the account; it can be restored for 30 days; then, or on
/// "delete forever", only a tombstone without content stays on the server.
class TrashService {
  TrashService(this._db, {this._media, this._clock = systemClock})
    : _registry = EntityRegistry(_db),
      _sync = SyncTracker(_db);

  final AppDatabase _db;
  final MediaStore? _media;
  final Clock _clock;
  final EntityRegistry _registry;
  final SyncTracker _sync;

  static const keepFor = Duration(days: 30);

  static String _type(TrashKind kind) => switch (kind) {
    TrashKind.observation => EntityTypes.observation,
    TrashKind.interview => EntityTypes.interview,
    TrashKind.evidence => EntityTypes.evidence,
    TrashKind.competitor => EntityTypes.competitor,
  };

  int _now() => _clock().millisecondsSinceEpoch;

  /// The element and, for an evidence, its photo.
  Future<List<(String, String)>> _parts(TrashKind kind, String id) async {
    final type = _type(kind);
    final json = await _registry.read(type, id);
    if (json == null) return const [];
    final media = kind == TrashKind.evidence
        ? json['mediaId'] as String?
        : null;
    return [(type, id), if (media != null) (EntityTypes.media, media)];
  }

  Future<void> _setDeleted(TrashKind kind, String id, int? at) =>
      _db.transaction(() async {
        for (final (type, partId) in await _parts(kind, id)) {
          final json = await _registry.read(type, partId);
          if (json == null) continue;
          await _registry.write(type, {
            ...json,
            'deletedAt': at,
            'updatedAt': _now(),
          });
          await _sync.markChanged(type, partId);
        }
      });

  Future<void> moveToTrash(TrashKind kind, String id) =>
      _setDeleted(kind, id, _now());

  Future<void> restore(TrashKind kind, String id) =>
      _setDeleted(kind, id, null);

  /// Deletes forever (the user confirmed). Nothing of the content stays:
  /// the local row goes now or as soon as the server has the tombstone,
  /// the photo file now, its server copy at the next synchronisation.
  Future<void> purge(TrashKind kind, String id) async {
    final media = <String>[];
    await _db.transaction(() async {
      for (final (type, partId) in await _parts(kind, id)) {
        if (type == EntityTypes.media) media.add(partId);
        if (await _sync.requestPurge(type, partId)) {
          await _registry.delete(type, partId);
        }
      }
      for (final mediaId in media) {
        await (_db.delete(
          _db.mediaUploads,
        )..where((u) => u.mediaId.equals(mediaId))).go();
        await _db.writeValue('${MediaSync.deletePrefix}$mediaId', '1');
      }
    });
    for (final mediaId in media) {
      _media?.deleteFile(mediaId);
    }
  }

  /// Elements deleted more than 30 days ago are deleted forever (at
  /// start-up). Returns how many.
  Future<int> purgeExpired() async {
    var purged = 0;
    final limit = _clock().subtract(keepFor);
    for (final item in await items()) {
      if (!item.deletedAt.isAfter(limit)) {
        await purge(item.kind, item.id);
        purged++;
      }
    }
    return purged;
  }

  /// The trash, most recently deleted first (purges already asked hidden).
  Future<List<TrashItem>> items() async {
    final purging = {
      for (final m in await (_db.select(
        _db.syncMetaEntries,
      )..where((t) => t.purgeRequested.equals(true))).get())
        m.entityId,
    };
    DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    TrashItem item(
      TrashKind kind,
      String id,
      String label,
      int deletedAt, {
      String? mediaId,
      int? amountMga,
    }) => TrashItem(
      kind: kind,
      id: id,
      label: label,
      deletedAt: at(deletedAt),
      purgeAt: at(deletedAt).add(keepFor),
      mediaId: mediaId,
      amountMga: amountMga,
    );

    final list = <TrashItem>[
      for (final r in await (_db.select(
        _db.observations,
      )..where((t) => t.deletedAt.isNotNull())).get())
        if (!purging.contains(r.id))
          item(TrashKind.observation, r.id, r.description, r.deletedAt!),
      for (final r in await (_db.select(
        _db.interviews,
      )..where((t) => t.deletedAt.isNotNull())).get())
        if (!purging.contains(r.id))
          item(TrashKind.interview, r.id, r.intervieweeAlias, r.deletedAt!),
      for (final r in await (_db.select(
        _db.evidences,
      )..where((t) => t.deletedAt.isNotNull())).get())
        if (!purging.contains(r.id))
          item(
            TrashKind.evidence,
            r.id,
            r.body ?? '',
            r.deletedAt!,
            mediaId: r.mediaId,
            amountMga: r.amountMga,
          ),
      for (final r in await (_db.select(
        _db.competitors,
      )..where((t) => t.deletedAt.isNotNull())).get())
        if (!purging.contains(r.id))
          item(TrashKind.competitor, r.id, r.name, r.deletedAt!),
    ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return list;
  }

  /// Ticks on every change of the trashable tables.
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.observations,
      _db.interviews,
      _db.evidences,
      _db.competitors,
      _db.syncMetaEntries,
    ]),
  );
}
