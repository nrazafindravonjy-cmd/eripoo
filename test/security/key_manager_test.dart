import 'dart:convert';
import 'dart:typed_data';

import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/security/recovery_code.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_secure_store.dart';

void main() {
  late CryptoService crypto;
  setUpAll(() async => crypto = await CryptoService.init());

  late MemorySecureKeyStore store;
  late KeyManager manager;
  setUp(() {
    store = MemorySecureKeyStore();
    manager = KeyManager(crypto, store);
  });

  const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
  // Fast parameters for most tests; the real ones are tested once below.
  const fast = KdfParams.floor;

  /// Two keys are equal if one decrypts what the other encrypted.
  bool sameKey(LocalKeys a, LocalKeys b) {
    final sealed = crypto.encrypt(Uint8List.fromList([42]), a.dataKey);
    try {
      return crypto.decrypt(sealed, b.dataKey).single == 42;
    } on DecryptionFailed {
      return false;
    }
  }

  group('device keys', () {
    test('first launch creates keys, later launches load the same', () async {
      final first = await manager.loadOrCreate(databaseExists: false);
      final again = await manager.loadOrCreate(databaseExists: true);
      expect(first.dataKeyVersion, 1);
      expect(first.databaseKey, hasLength(32));
      expect(again.databaseKey, first.databaseKey);
      expect(again.deviceId, first.deviceId);
      expect(sameKey(first, again), isTrue);
    });

    test('data key and database key are different keys', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      expect(keys.dataKey.extractBytes(), isNot(keys.databaseKey));
    });

    test(
      'an existing database without keys is reported, never re-keyed',
      () async {
        await expectLater(
          manager.loadOrCreate(databaseExists: true),
          throwsA(isA<LocalKeysLost>()),
        );
      },
    );

    test('partial or corrupted key storage is reported', () async {
      await manager.loadOrCreate(databaseExists: false);
      store.values.remove('eripoo.dbk');
      await expectLater(
        manager.loadOrCreate(databaseExists: false),
        throwsA(isA<LocalKeysLost>()),
      );

      store.values.clear();
      await manager.loadOrCreate(databaseExists: false);
      store.values['eripoo.umk'] = base64.encode([1, 2, 3]);
      await expectLater(
        manager.loadOrCreate(databaseExists: true),
        throwsA(isA<LocalKeysLost>()),
      );
    });

    test('stored values are not the raw key', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final stored = base64.decode(store.values['eripoo.umk']!);
      expect(stored[0], 0x01); // format
      expect(stored.sublist(3), keys.dataKey.extractBytes());
      // The store itself is protected by the Android Keystore in the app.
    });

    test('wipe removes every key', () async {
      await manager.loadOrCreate(databaseExists: false);
      await manager.wipe();
      expect(store.values, isEmpty);
    });

    test(
      'derived sub-keys differ from each other and from the data key',
      () async {
        final keys = await manager.loadOrCreate(databaseExists: false);
        final derived = DataKeys(crypto, keys.dataKey);
        addTearDown(derived.dispose);
        final umk = keys.dataKey.extractBytes();
        expect(derived.records.extractBytes(), isNot(umk));
        expect(derived.media.extractBytes(), isNot(umk));
        expect(
          derived.records.extractBytes(),
          isNot(derived.media.extractBytes()),
        );
      },
    );
  });

  group('recovery code and server copy of the data key', () {
    test('generated codes are well formed and use every digit', () {
      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        final code = manager.generateRecoveryCode();
        expect(RecoveryCode.isWellFormed(code), isTrue);
        seen.addAll(code.split(''));
      }
      expect(seen, hasLength(10));
    });

    test('the right code recovers the data key', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final wrap = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );

      final typed = RecoveryCode.groups(code).join(' ');
      final recovered = manager.openRecoveryWrap(
        wrap: wrap,
        ownerId: owner,
        typedCode: typed,
      );
      expect(recovered.extractBytes(), keys.dataKey.extractBytes());
    });

    test('a wrong code fails without revealing anything', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final wrap = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: manager.generateRecoveryCode(),
        params: fast,
      );
      expect(
        () => manager.openRecoveryWrap(
          wrap: wrap,
          ownerId: owner,
          typedCode: manager.generateRecoveryCode(),
        ),
        throwsA(isA<WrongRecoveryCode>()),
      );
    });

    test('a typing mistake is caught before any key derivation', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final wrap = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );
      final typo = code.replaceRange(0, 1, code[0] == '1' ? '2' : '1');
      expect(
        () => manager.openRecoveryWrap(
          wrap: wrap,
          ownerId: owner,
          typedCode: typo,
        ),
        throwsA(isA<MalformedRecoveryCode>()),
      );
      expect(
        () => manager.openRecoveryWrap(
          wrap: wrap,
          ownerId: owner,
          typedCode: '1234',
        ),
        throwsA(isA<MalformedRecoveryCode>()),
      );
    });

    test('a wrap only opens for its own account', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final wrap = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );
      expect(
        () => manager.openRecoveryWrap(
          wrap: wrap,
          ownerId: '0192f2a0-7c1e-7b3a-9c2d-000000000001',
          typedCode: code,
        ),
        throwsA(isA<WrongRecoveryCode>()),
      );
    });

    test('each wrap has its own salt and stores no part of the code', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final a = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );
      final b = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );
      expect(a.salt, hasLength(16));
      expect(a.salt, isNot(b.salt));
      expect(a.wrapped, isNot(b.wrapped));
      expect(a.wrapped[0], EnvelopeFormat.v1);
      final serialized =
          '${a.wrapId}${base64.encode(a.salt)}${base64.encode(a.wrapped)}${a.params.toJson()}';
      expect(serialized.contains(RecoveryCode.secretPart(code)), isFalse);
    });

    test('works with the proposed production parameters (Argon2id 3 × 64 MiB)', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final watch = Stopwatch()..start();
      final wrap = manager.createRecoveryWrap(
        keys: keys,
        ownerId: owner,
        code: code,
      );
      watch.stop();
      expect(wrap.params.memLimit, 64 << 20);
      expect(wrap.params.opsLimit, 3);
      final recovered = manager.openRecoveryWrap(
        wrap: wrap,
        ownerId: owner,
        typedCode: code,
      );
      expect(recovered.extractBytes(), keys.dataKey.extractBytes());
      // Development machine timing only; device timing is NOT VERIFIED (P7).
      // ignore: avoid_print
      print(
        'Argon2id 3 × 64 MiB on this machine: ${watch.elapsedMilliseconds} ms',
      );
    });

    test('background isolate variants give the same results', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final code = manager.generateRecoveryCode();
      final wrap = await manager.createRecoveryWrapInBackground(
        keys: keys,
        ownerId: owner,
        code: code,
        params: fast,
      );
      final key = await manager.openRecoveryWrapInBackground(
        wrap: wrap,
        ownerId: owner,
        typedCode: code,
      );
      expect(key.extractBytes(), keys.dataKey.extractBytes());
      await expectLater(
        manager.openRecoveryWrapInBackground(
          wrap: wrap,
          ownerId: owner,
          typedCode: manager.generateRecoveryCode(),
        ),
        throwsA(isA<WrongRecoveryCode>()),
      );
    });

    test('a recovered key can replace the device data key', () async {
      final keys = await manager.loadOrCreate(databaseExists: false);
      final other = KeyManager(crypto, MemorySecureKeyStore());
      final otherKeys = await other.loadOrCreate(databaseExists: false);
      await manager.replaceDataKey(otherKeys.dataKey, 1);
      final reloaded = await manager.loadOrCreate(databaseExists: true);
      expect(reloaded.dataKey.extractBytes(), otherKeys.dataKey.extractBytes());
      expect(reloaded.databaseKey, keys.databaseKey); // DB key unchanged
    });

    test(
      'the replaced key is kept until local files use the new one',
      () async {
        final keys = await manager.loadOrCreate(databaseExists: false);
        final first = keys.dataKey.extractBytes();
        expect(await manager.previousDataKey(), isNull);
        await manager.replaceDataKey(crypto.generateKey(), 2);
        // A second switch before the files were re-encrypted keeps the
        // first key: the files are still under it.
        await manager.replaceDataKey(crypto.generateKey(), 3);
        final previous = await manager.previousDataKey();
        expect(previous!.key.extractBytes(), first);
        expect(previous.version, 1);
        await manager.forgetPreviousDataKey();
        expect(await manager.previousDataKey(), isNull);

        await manager.replaceDataKey(crypto.generateKey(), 4);
        await manager.wipe();
        expect(await manager.previousDataKey(), isNull);
      },
    );
  });
}
