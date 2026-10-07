import 'package:drift/drift.dart';

import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../security/crypto_service.dart';
import '../../../sync/remote/media_remote.dart';
import '../../../sync/remote/sync_remote.dart';
import '../data/media_store.dart';

/// What one pass of media sending did.
class MediaPassReport {
  const MediaPassReport({
    required this.uploaded,
    required this.waiting,
    required this.refused,
    this.interrupted = false,
  });

  final int uploaded;

  /// Still to send (no network, Wi-Fi required, server busy).
  final int waiting;

  /// Refused by the server (kept on the phone, retried in an hour).
  final int refused;

  /// Stopped by a network failure: the rest is retried with the backoff.
  final bool interrupted;
}

/// Sends the photos taken on this phone and fetches the others' on demand
/// (docs/OFFLINE_SYNC.md §9). Files are sealed again for the account
/// before leaving the phone; the server only ever gets ciphertext.
///
/// Runs after the records' synchronisation: a file is never sent before
/// its metadata, so another phone that receives it knows its hash.
class MediaSync {
  MediaSync({
    required this._db,
    required this._store,
    required this._remote,
    required this._ownerId,
    this._clock = systemClock,
  });

  final AppDatabase _db;
  final MediaStore _store;
  final MediaRemote _remote;
  final String _ownerId;
  final Clock _clock;

  static const refusedDelay = Duration(hours: 1);

  int _now() => _clock().millisecondsSinceEpoch;

  /// Sends the waiting files, oldest first. Stops at the first network
  /// failure ([RemoteUnavailable] is not thrown: the rest waits).
  Future<MediaPassReport> uploadPending() async {
    final now = _now();
    final queue =
        await (_db.select(_db.mediaUploads)
              ..where(
                (u) =>
                    u.uploadedAt.isNull() &
                    (u.nextAttemptAt.isNull() |
                        u.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..orderBy([(u) => OrderingTerm(expression: u.mediaId)]))
            .get();
    var uploaded = 0;
    var refused = 0;
    for (var i = 0; i < queue.length; i++) {
      final item = queue[i];
      final row = await (_db.select(
        _db.mediaItems,
      )..where((m) => m.id.equals(item.mediaId))).getSingleOrNull();
      // In the trash: not sent while there (it may never be needed), not
      // forgotten either (it may be restored).
      if (row != null && row.deletedAt != null) continue;
      final sealed = row == null
          ? null
          : await _store.sealedForAccount(item.mediaId, _ownerId);
      if (sealed == null) {
        // Deleted forever, or the file is gone: nothing to send.
        await _forget(item.mediaId);
        continue;
      }
      try {
        await _remote.upload(item.mediaId, sealed);
        await (_db.update(_db.mediaUploads)
              ..where((u) => u.mediaId.equals(item.mediaId)))
            .write(MediaUploadsCompanion(uploadedAt: Value(_now())));
        uploaded++;
      } on RemoteRejected {
        refused++;
        await (_db.update(
          _db.mediaUploads,
        )..where((u) => u.mediaId.equals(item.mediaId))).write(
          MediaUploadsCompanion(
            attempts: Value(item.attempts + 1),
            nextAttemptAt: Value(_now() + refusedDelay.inMilliseconds),
          ),
        );
      } on RemoteUnavailable {
        return MediaPassReport(
          uploaded: uploaded,
          waiting: await waitingCount(),
          refused: refused,
          interrupted: true,
        );
      }
    }
    return MediaPassReport(
      uploaded: uploaded,
      waiting: await waitingCount(),
      refused: refused,
    );
  }

  Future<void> _forget(String mediaId) => (_db.delete(
    _db.mediaUploads,
  )..where((u) => u.mediaId.equals(mediaId))).go();

  /// Files of this phone not yet on the server (trash excluded).
  Future<int> waitingCount() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM media_uploads u '
          'JOIN media_items m ON m.id = u.media_id '
          'WHERE u.uploaded_at IS NULL AND m.deleted_at IS NULL',
          readsFrom: {_db.mediaUploads, _db.mediaItems},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Key prefix of server files to delete (photos deleted forever).
  static const deletePrefix = 'media.delete.';

  /// Deletes the server copies of photos deleted forever. Stops quietly
  /// at the first network failure (retried at the next pass).
  Future<int> deleteRemoved() async {
    final pending = await (_db.select(
      _db.localKeyValues,
    )..where((k) => k.key.like('$deletePrefix%'))).get();
    var deleted = 0;
    for (final entry in pending) {
      final id = entry.key.substring(deletePrefix.length);
      try {
        await _remote.delete(id);
      } on RemoteUnavailable {
        break;
      } on RemoteRejected {
        // Not ours to delete (or already gone): nothing more to do.
      }
      await _db.deleteValue(entry.key);
      deleted++;
    }
    return deleted;
  }

  /// Fetches a file known by its metadata only (taken on another phone).
  /// Returns false when the server does not have it yet (the other phone
  /// has not sent it). Throws [RemoteUnavailable] offline, and
  /// [MediaCorrupted] / [DecryptionFailed] for a file that does not match.
  Future<bool> fetch(String mediaId) async {
    if (_store.hasFile(mediaId)) return true;
    final sealed = await _remote.download(mediaId);
    if (sealed == null) return false;
    await _store.storeFromAccount(mediaId, _ownerId, sealed);
    return true;
  }
}
