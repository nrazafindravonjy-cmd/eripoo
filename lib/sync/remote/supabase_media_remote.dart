import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_remote.dart';
import 'sync_remote.dart';

/// [MediaRemote] over Supabase Storage. Checked against a running Supabase
/// by the contract tests (test/contract/, CI job "Supabase local").
class SupabaseMediaRemote implements MediaRemote {
  SupabaseMediaRemote(this._client);

  final SupabaseClient _client;

  static const bucket = 'user-media';

  StorageFileApi get _files => _client.storage.from(bucket);

  String _path(String mediaId) {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const NotAuthenticated();
    return '$uid/$mediaId';
  }

  @override
  Future<void> upload(String mediaId, Uint8List sealed) async {
    final path = _path(mediaId);
    try {
      await _files.uploadBinary(
        path,
        sealed,
        // Not cached: the hosted CDN kept serving a deleted file (contract
        // test against the development project, 2026-10-22).
        fileOptions: const FileOptions(
          contentType: 'application/octet-stream',
          cacheControl: '0',
        ),
      );
    } on StorageException catch (e) {
      // Already there: a previous upload whose response was lost.
      if (e.statusCode == '409' || e.error == 'Duplicate') return;
      throw mapStorageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<Uint8List?> download(String mediaId) async {
    final path = _path(mediaId);
    try {
      return await _files.download(path);
    } on StorageException catch (e) {
      // A missing file and a file the policies hide both read as "not
      // found": not available to this session.
      if (isStorageNotFound(e)) return null;
      throw mapStorageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<void> deleteAll() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const NotAuthenticated();
    try {
      // Listed and removed page by page until the folder is empty.
      for (var guard = 0; guard < 100; guard++) {
        final page = await _files.list(
          path: uid,
          searchOptions: const SearchOptions(limit: 100),
        );
        if (page.isEmpty) return;
        await _files.remove([for (final f in page) '$uid/${f.name}']);
      }
    } on StorageException catch (e) {
      throw mapStorageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<void> delete(String mediaId) async {
    final path = _path(mediaId);
    try {
      await _files.remove([path]);
    } on StorageException catch (e) {
      throw mapStorageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }
}

bool isStorageNotFound(StorageException e) =>
    e.statusCode == '404' ||
    e.error == 'not_found' ||
    e.message.toLowerCase().contains('not found');

/// Refusals are permanent (never retried); anything else is retried later.
SyncRemoteFailure mapStorageError(StorageException e) => switch (e.statusCode) {
  '401' => const NotAuthenticated(),
  '400' || '403' || '413' || '415' || '422' => const RemoteRejected(),
  _ => const RemoteUnavailable(),
};
