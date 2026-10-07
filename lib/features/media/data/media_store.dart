import 'dart:io';

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
    this._clock = systemClock,
  }) : _crypto = crypto,
       _envelopes = MediaEnvelopes(crypto),
       _sync = SyncTracker(_db);

  final AppDatabase _db;
  final CryptoService _crypto;
  final MediaEnvelopes _envelopes;
  final SecureKey _key;
  final int _umkVersion;
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
    final sealed = _envelopes.seal(
      plaintext: bytes,
      mediaKey: _key,
      umkVersion: _umkVersion,
      mediaId: id,
    );
    await _dir.create(recursive: true);
    final part = File('${fileOf(id).path}.part');
    await part.writeAsBytes(sealed, flush: true);
    await part.rename(fileOf(id).path);
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
      });
    } on Object {
      await fileOf(id).delete().catchError((Object _) => fileOf(id));
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
    final plain = _envelopes.open(
      envelope: await file.readAsBytes(),
      mediaKey: _key,
      mediaId: mediaId,
    );
    if (_crypto.hashHex(plain) != row.contentHash) throw const MediaCorrupted();
    return plain;
  }

  /// Moves the media to the trash and deletes its encrypted file.
  Future<void> remove(String mediaId) async {
    await _db.transaction(() async {
      final now = _clock().millisecondsSinceEpoch;
      await (_db.update(
        _db.mediaItems,
      )..where((t) => t.id.equals(mediaId))).write(
        MediaItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await _sync.markChanged(EntityTypes.media, mediaId);
    });
    final file = fileOf(mediaId);
    if (file.existsSync()) await file.delete();
  }

  /// Deletes files with no live row: an interrupted save (`.part`) or a
  /// crash between the file and the database. Returns how many.
  Future<int> purgeOrphans() async {
    if (!_dir.existsSync()) return 0;
    final live = {
      for (final r in await (_db.select(
        _db.mediaItems,
      )..where((t) => t.deletedAt.isNull())).get())
        r.id,
    };
    var removed = 0;
    for (final entity in _dir.listSync().whereType<File>()) {
      final name = entity.uri.pathSegments.last;
      final id = name.endsWith('.bin')
          ? name.substring(0, name.length - 4)
          : null;
      if (id == null || !live.contains(id)) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }
}
