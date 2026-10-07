// Encrypted photos (docs/SECURITY.md §4.7): never plain on disk, bound to
// their id and key, capped at 10 MiB. Fictitious bytes only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/data/local/entity_types.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// A recognisable "photo": a JPEG header and a marker that must never be
/// found on disk.
Uint8List fakePhoto([int size = 4096]) {
  final marker = 'PHOTO-EN-CLAIR-'.codeUnits;
  return Uint8List.fromList([
    0xff,
    0xd8,
    0xff,
    for (var i = 0; i < size; i++) marker[i % marker.length],
  ]);
}

bool contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory dir;
  late MediaStore store;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    dir = Directory.systemTemp.createTempSync('eripoo_media');
    store = MediaStore(
      db: db,
      crypto: crypto,
      key: crypto.generateKey(),
      umkVersion: 1,
      dir: dir,
    );
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'round trip; the file on disk holds no plain byte of the photo',
    () async {
      final photo = fakePhoto();
      final id = await store.addPhoto(photo, mime: 'image/jpeg');
      expect(await store.read(id), photo);

      final onDisk = store.fileOf(id).readAsBytesSync();
      expect(onDisk[0], EnvelopeFormat.v1);
      expect(contains(onDisk, 'PHOTO-EN-CLAIR-'.codeUnits), isFalse);
      expect(contains(onDisk, [0xff, 0xd8, 0xff]), isFalse);
      // Only the encrypted file is left in the directory.
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['$id.bin']);

      final row = await db.select(db.mediaItems).getSingle();
      expect(row.sizeBytes, photo.length);
      expect(row.mime, 'image/jpeg');
      final pending = await db.select(db.syncMetaEntries).get();
      expect(
        pending.where(
          (p) => p.entityType == EntityTypes.media && p.entityId == id,
        ),
        hasLength(1),
      );
    },
  );

  test('another key, another id or a modified file cannot be read', () async {
    final id = await store.addPhoto(fakePhoto(), mime: 'image/png');
    final other = MediaStore(
      db: db,
      crypto: crypto,
      key: crypto.generateKey(),
      umkVersion: 1,
      dir: dir,
    );
    await expectLater(other.read(id), throwsA(isA<DecryptionFailed>()));

    // The same encrypted bytes under another media id.
    final id2 = await store.addPhoto(fakePhoto(10), mime: 'image/png');
    store.fileOf(id2).writeAsBytesSync(store.fileOf(id).readAsBytesSync());
    await expectLater(store.read(id2), throwsA(isA<DecryptionFailed>()));

    final bytes = store.fileOf(id).readAsBytesSync();
    bytes[bytes.length - 1] ^= 1;
    store.fileOf(id).writeAsBytesSync(bytes);
    await expectLater(store.read(id), throwsA(isA<DecryptionFailed>()));
  });

  test('a recorded hash that does not match is reported', () async {
    final id = await store.addPhoto(fakePhoto(), mime: 'image/webp');
    await db.customStatement(
      "update media_items set content_hash = '00' where id = ?",
      [id],
    );
    await expectLater(store.read(id), throwsA(isA<MediaCorrupted>()));
  });

  test(
    '10 MiB cap and photo types only, nothing written when refused',
    () async {
      await expectLater(
        store.addPhoto(
          Uint8List(MediaEnvelopes.maxPlainBytes + 1),
          mime: 'image/jpeg',
        ),
        throwsA(isA<MediaTooLarge>()),
      );
      await expectLater(
        store.addPhoto(fakePhoto(), mime: 'audio/mpeg'),
        throwsA(isA<UnsupportedMedia>()),
      );
      expect(dir.listSync(), isEmpty);
      expect(await db.select(db.mediaItems).get(), isEmpty);
      final id = await store.addPhoto(
        Uint8List(MediaEnvelopes.maxPlainBytes),
        mime: 'image/jpeg',
      );
      expect((await store.read(id))!.length, MediaEnvelopes.maxPlainBytes);
    },
  );

  test('remove deletes the file; a missing file reads as null', () async {
    final id = await store.addPhoto(fakePhoto(), mime: 'image/jpeg');
    await store.remove(id);
    expect(store.fileOf(id).existsSync(), isFalse);
    expect(await store.read(id), isNull);

    final id2 = await store.addPhoto(fakePhoto(), mime: 'image/jpeg');
    store.fileOf(id2).deleteSync(); // e.g. metadata synced, file not yet
    expect(await store.read(id2), isNull);
  });

  test('interrupted saves and orphans are purged, live files kept', () async {
    final id = await store.addPhoto(fakePhoto(), mime: 'image/jpeg');
    File('${dir.path}/0192f2a0-0000-7000-8000-00000000abcd.bin.part')
        .writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/0192f2a0-0000-7000-8000-00000000abce.bin')
        .writeAsBytesSync([4, 5, 6]);
    expect(await store.purgeOrphans(), 2);
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['$id.bin']);
    expect(await store.read(id), isNotNull);
  });
}
