import 'dart:typed_data';

/// Encrypted media files on the server (bucket `user-media`,
/// `{owner_id}/{media_id}`, docs/OFFLINE_SYNC.md §9). The server only sees
/// opaque bytes: files are sealed for the account on the phone before
/// upload (docs/SECURITY.md §4.7).
///
/// Errors are the [SyncRemoteFailure]s of `sync_remote.dart`: a refused
/// file (too large, wrong path, session of a removed device) is
/// `RemoteRejected`.
abstract interface class MediaRemote {
  /// Idempotent: uploading an id that is already there succeeds (a lost
  /// response is retried without error). Files are never overwritten.
  Future<void> upload(String mediaId, Uint8List sealed);

  /// The sealed bytes, or null when the server has no such file (not yet
  /// uploaded by the other device, or deleted).
  Future<Uint8List?> download(String mediaId);

  /// Idempotent.
  Future<void> delete(String mediaId);
}
