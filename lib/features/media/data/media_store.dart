import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../../../security/crypto_service.dart';
import '../../../security/envelopes.dart';

/// The file is larger than the cap (10 MiB, D15).
class MediaTooLarge implements Exception {
  const MediaTooLarge();
}

/// Only photos (JPEG, PNG, WebP) in Phase 4.
class UnsupportedMedia implements Exception {
  const UnsupportedMedia();
}

/// The decrypted file does not match its recorded hash.
class MediaCorrupted implements Exception {
  const MediaCorrupted();
}

/// Encrypted files in the app's private directory (docs/SECURITY.md §4.7).
/// Plain bytes are never written to disk: they are encrypted in memory,
/// then written to `<id>.part` and renamed, so a crash leaves either no
/// file or a complete encrypted one. The metadata row is synced; the
/// file itself is uploaded in Phase 5.
class MediaStore {
  MediaStore({
    required this._db,
    required CryptoService crypto,
    required this._key,
    required this._umkVersion,
    required this._dir,
    this._previousKey,
    this._clock = systemClock,
  }) : _crypto = crypto,
       _envelopes = MediaEnvelopes(crypto),
       _sync = SyncTracker(_db);

  final AppDatabase _db;
  final CryptoService _crypto;
  final MediaEnvelopes _envelopes;
  final SecureKey _key;
  final int _umkVersion;

  /// The media sub-key of the data key replaced by a recovery or a device
  /// transfer, until [resealAll] has re-encrypted every file.
  final SecureKey? _previousKey;
  final Directory _dir;
  final Clock _clock;
  final SyncTracker _sync;

  static const photoTypes = {'image/jpeg', 'image/png', 'image/webp'};

  File fileOf(String mediaId) => File('${_dir.path}/$mediaId.bin');

  /// Encrypts and stores a photo; returns its media id.
  Future<String> addPhoto(Uint8List bytes, {required String mime}) async {
    if (!photoTypes.contains(mime)) throw const UnsupportedMedia();
    if (bytes.length > MediaEnvelopes.maxPlainBytes) {
      throw const MediaTooLarge();
    }
    final id = Ids.newId();
    final sealed = await _seal(bytes, id, MediaEnvelopes.localOwner);
    // Synchronous writes: photos are small (≈ 300 KB after resizing) and
    // a write cannot be left half-done by a suspended future.
    _dir.createSync(recursive: true);
    final part = File('${fileOf(id).path}.part')
      ..writeAsBytesSync(sealed, flush: true);
    part.renameSync(fileOf(id).path);
    final now = _clock().millisecondsSinceEpoch;
    try {
      await _db.transaction(() async {
        await _db
            .into(_db.mediaItems)
            .insert(
              MediaItemsCompanion.insert(
                id: id,
                kind: 'photo',
                mime: mime,
                sizeBytes: bytes.length,
                contentHash: _crypto.hashHex(bytes),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _sync.markChanged(EntityTypes.media, id);
        // The file itself is sent later (Wi-Fi by default).
        await _db
            .into(_db.mediaUploads)
            .insert(MediaUploadsCompanion.insert(mediaId: id));
      });
    } on Object {
      if (fileOf(id).existsSync()) fileOf(id).deleteSync();
      rethrow;
    }
    return id;
  }

  /// The plain bytes, or null when the file is not on this device (its
  /// metadata came from another device; files sync in Phase 5).
  Future<Uint8List?> read(String mediaId) async {
    final row =
        await (_db.select(_db.mediaItems)
              ..where((t) => t.id.equals(mediaId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    final file = fileOf(mediaId);
    if (row == null || !file.existsSync()) return null;
    final plain = await _openLocal(file.readAsBytesSync(), mediaId);
    if (_crypto.hashHex(plain) != row.contentHash) throw const MediaCorrupted();
    return plain;
  }

  /// Files above this size are encrypted and decrypted on a background
  /// isolate: a 10 MiB file blocked the interface ≈ 0.7 s on emulators
  /// (docs/DEVICE_TESTS.md §2ter). Small photos stay on this isolate,
  /// where the cost (≈ 40 ms for 300 KB) is lower than starting one.
  static const backgroundThreshold = 1024 * 1024;

  Future<Uint8List> _seal(Uint8List plain, String mediaId, String owner) {
    if (plain.length < backgroundThreshold) {
      return Future.value(
        _envelopes.seal(
          plaintext: plain,
          mediaKey: _key,
          umkVersion: _umkVersion,
          mediaId: mediaId,
          ownerId: owner,
        ),
      );
    }
    // Only plain values go to the isolate, never `this` (native keys, the
    // database).
    final version = _umkVersion;
    return _withKeyBytes(
      (key) => Isolate.run(
        () => _sealInIsolate(key, plain, version, mediaId, owner),
      ),
    );
  }

  /// Opens with the current key, in the background for large files; small
  /// files fall back to the previous key (after a key switch).
  Future<Uint8List> _openLocal(Uint8List envelope, String mediaId) async {
    if (envelope.length < backgroundThreshold || _previousKey != null) {
      return _open(envelope, mediaId).$1;
    }
    return _withKeyBytes(
      (key) => Isolate.run(
        () => _openInIsolate(key, envelope, mediaId, MediaEnvelopes.localOwner),
      ),
    );
  }

  /// The media key as bytes for a background isolate (which loads its own
  /// libsodium), zeroed afterwards: a best effort, as the Dart VM may keep
  /// copies (same trade-off as the recovery code, KeyManager).
  Future<T> _withKeyBytes<T>(Future<T> Function(Uint8List key) run) async {
    final key = _key.extractBytes();
    try {
      return await run(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  // ---------------------------------------------------------- server copy

  /// The file sealed for the account [ownerId], ready to upload; null when
  /// it is not on this phone.
  Future<Uint8List?> sealedForAccount(String mediaId, String ownerId) async {
    final file = fileOf(mediaId);
    if (!file.existsSync()) return null;
    final plain = await _openLocal(file.readAsBytesSync(), mediaId);
    try {
      return await _seal(plain, mediaId, ownerId);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Stores a file downloaded from the account [ownerId] after checking it
  /// is the one described by its metadata (hash). Throws [MediaCorrupted]
  /// (or `DecryptionFailed` for a file not sealed with this key).
  Future<void> storeFromAccount(
    String mediaId,
    String ownerId,
    Uint8List sealed,
  ) async {
    final row = await (_db.select(
      _db.mediaItems,
    )..where((t) => t.id.equals(mediaId))).getSingleOrNull();
    if (row == null) throw const MediaCorrupted();
    final Uint8List plain;
    if (sealed.length < backgroundThreshold) {
      plain = _envelopes.open(
        envelope: sealed,
        mediaKey: _key,
        mediaId: mediaId,
        ownerId: ownerId,
      );
    } else {
      plain = await _withKeyBytes(
        (key) =>
            Isolate.run(() => _openInIsolate(key, sealed, mediaId, ownerId)),
      );
    }
    try {
      if (_crypto.hashHex(plain) != row.contentHash) {
        throw const MediaCorrupted();
      }
      final local = await _seal(plain, mediaId, MediaEnvelopes.localOwner);
      _dir.createSync(recursive: true);
      final part = File('${fileOf(mediaId).path}.part')
        ..writeAsBytesSync(local, flush: true);
      part.renameSync(fileOf(mediaId).path);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Whether the file is on this phone (it may be only on the server).
  bool hasFile(String mediaId) => fileOf(mediaId).existsSync();

  /// The plain bytes, and whether they were opened with the previous key.
  (Uint8List, bool) _open(Uint8List envelope, String mediaId) {
    try {
      return (
        _envelopes.open(envelope: envelope, mediaKey: _key, mediaId: mediaId),
        false,
      );
    } on DecryptionFailed {
      final previous = _previousKey;
      if (previous == null) rethrow;
      return (
        _envelopes.open(
          envelope: envelope,
          mediaKey: previous,
          mediaId: mediaId,
        ),
        true,
      );
    }
  }

  /// Re-encrypts with the current key every file still under the previous
  /// one, each through `.part` + rename (a crash leaves the old complete
  /// file, still readable with the previous key). Returns how many files
  /// could be opened with neither key (left untouched).
  Future<int> resealAll() async {
    if (_previousKey == null || !_dir.existsSync()) return 0;
    // Trashed photos too: they can still be restored.
    final rows = await _db.select(_db.mediaItems).get();
    var unreadable = 0;
    for (final row in rows) {
      final file = fileOf(row.id);
      if (!file.existsSync()) continue;
      final Uint8List plain;
      final bool old;
      try {
        (plain, old) = _open(file.readAsBytesSync(), row.id);
      } on DecryptionFailed {
        unreadable++;
        continue;
      }
      if (!old) continue;
      final sealed = _envelopes.seal(
        plaintext: plain,
        mediaKey: _key,
        umkVersion: _umkVersion,
        mediaId: row.id,
      );
      plain.fillRange(0, plain.length, 0);
      final part = File('${file.path}.part')
        ..writeAsBytesSync(sealed, flush: true);
      part.renameSync(file.path);
    }
    return unreadable;
  }

  /// Deletes the encrypted file of a media deleted forever (the trash
  /// keeps it until then, so a restored photo is still there).
  void deleteFile(String mediaId) {
    final file = fileOf(mediaId);
    if (file.existsSync()) file.deleteSync();
  }

  /// Deletes files with no row (trashed rows keep theirs): an interrupted
  /// save (`.part`), a crash between the file and the database, or a media
  /// deleted forever on another phone. Returns how many.
  Future<int> purgeOrphans() async {
    if (!_dir.existsSync()) return 0;
    final live = {for (final r in await _db.select(_db.mediaItems).get()) r.id};
    var removed = 0;
    for (final entity in _dir.listSync().whereType<File>()) {
      final name = entity.uri.pathSegments.last;
      final id = name.endsWith('.bin')
          ? name.substring(0, name.length - 4)
          : null;
      if (id == null || !live.contains(id)) {
        entity.deleteSync();
        removed++;
      }
    }
    return removed;
  }
}

// Isolate entry points: top-level, so the closures capture plain values.

Future<Uint8List> _sealInIsolate(
  Uint8List key,
  Uint8List plain,
  int umkVersion,
  String mediaId,
  String owner,
) async {
  final crypto = await CryptoService.init();
  final secure = crypto.keyFromBytes(key);
  key.fillRange(0, key.length, 0);
  try {
    return MediaEnvelopes(crypto).seal(
      plaintext: plain,
      mediaKey: secure,
      umkVersion: umkVersion,
      mediaId: mediaId,
      ownerId: owner,
    );
  } finally {
    secure.dispose();
  }
}

Future<Uint8List> _openInIsolate(
  Uint8List key,
  Uint8List envelope,
  String mediaId,
  String owner,
) async {
  final crypto = await CryptoService.init();
  final secure = crypto.keyFromBytes(key);
  key.fillRange(0, key.length, 0);
  try {
    return MediaEnvelopes(crypto).open(
      envelope: envelope,
      mediaKey: secure,
      mediaId: mediaId,
      ownerId: owner,
    );
  } finally {
    secure.dispose();
  }
}
