import 'dart:convert';
import 'dart:typed_data';

import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late CryptoService crypto;
  setUpAll(() async => crypto = await CryptoService.init());

  const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
  const otherOwner = '0192f2a0-7c1e-7b3a-9c2d-000000000001';
  const record = '0192f2a1-0000-7000-8000-000000000042';
  const otherRecord = '0192f2a1-0000-7000-8000-000000000043';

  test('XChaCha20-Poly1305 matches the published test vector', () {
    // draft-irtf-cfrg-xchacha, appendix A.3.1.
    final key = crypto.keyFromBytes(
      _hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f'),
    );
    final nonce = _hex('404142434445464748494a4b4c4d4e4f5051525354555657');
    final ad = _hex('50515253c0c1c2c3c4c5c6c7');
    final message = utf8.encode(
      "Ladies and Gentlemen of the class of '99: If I could offer you only "
      'one tip for the future, sunscreen would be it.',
    );
    final out = crypto.sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
      message: Uint8List.fromList(message),
      nonce: nonce,
      key: key,
      additionalData: ad,
    );
    expect(
      _toHex(out.sublist(0, 32)),
      'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb',
    );
    expect(
      _toHex(out.sublist(out.length - 16)),
      'c0875924c1c7987947deafd8780acf49',
    );
    key.dispose();
  });

  group('authenticated encryption', () {
    test('round-trips and uses a fresh nonce each time', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final message = Uint8List.fromList(utf8.encode('Mon projet'));
      final a = crypto.encrypt(message, key);
      final b = crypto.encrypt(message, key);
      expect(a, isNot(equals(b)));
      expect(crypto.decrypt(a, key), message);
    });

    test('rejects tampering, wrong key and wrong associated data', () {
      final key = crypto.generateKey();
      final other = crypto.generateKey();
      addTearDown(key.dispose);
      addTearDown(other.dispose);
      final ad = Uint8List.fromList([1, 2, 3]);
      final sealed = crypto.encrypt(Uint8List.fromList([9, 9, 9]), key, ad: ad);

      final tampered = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
      expect(
        () => crypto.decrypt(tampered, key, ad: ad),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => crypto.decrypt(sealed, other, ad: ad),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => crypto.decrypt(sealed, key),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => crypto.decrypt(Uint8List(5), key),
        throwsA(isA<DecryptionFailed>()),
      );
    });
  });

  group('record envelopes v1', () {
    late RecordEnvelopes envelopes;
    setUp(() => envelopes = RecordEnvelopes(crypto));

    Uint8List sealFor(
      String ownerId,
      String recordId,
      Uint8List data,
      SecureKey key,
    ) => envelopes.seal(
      plaintext: data,
      recordKey: key,
      umkVersion: 1,
      ownerId: ownerId,
      recordId: recordId,
    );

    test('round-trip, header and padded length', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final data = Uint8List.fromList(utf8.encode('{"t":"hypothesis"}'));
      final envelope = sealFor(owner, record, data, key);

      expect(envelope[0], EnvelopeFormat.v1);
      expect(EnvelopeHeader.read(envelope).umkVersion, 1);
      // header (3) + nonce (24) + padded plaintext + tag (16)
      expect((envelope.length - 3 - 24 - 16) % EnvelopeFormat.recordPadding, 0);
      expect(
        envelopes.open(
          envelope: envelope,
          recordKey: key,
          ownerId: owner,
          recordId: record,
        ),
        data,
      );
    });

    test('hides the exact length of short texts', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final short = sealFor(owner, record, Uint8List.fromList([1]), key);
      final longer = sealFor(owner, record, Uint8List(200), key);
      expect(short.length, longer.length);
    });

    test('an envelope moved to another record or account is rejected', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final envelope = sealFor(owner, record, Uint8List.fromList([1, 2]), key);
      expect(
        () => envelopes.open(
          envelope: envelope,
          recordKey: key,
          ownerId: owner,
          recordId: otherRecord,
        ),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => envelopes.open(
          envelope: envelope,
          recordKey: key,
          ownerId: otherOwner,
          recordId: record,
        ),
        throwsA(isA<DecryptionFailed>()),
      );
    });

    test('an unknown format version is rejected', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final envelope = sealFor(owner, record, Uint8List.fromList([1]), key)
        ..[0] = 0x02;
      expect(
        () => envelopes.open(
          envelope: envelope,
          recordKey: key,
          ownerId: owner,
          recordId: record,
        ),
        throwsA(isA<DecryptionFailed>()),
      );
    });

    test('envelope contains no plaintext', () {
      final key = crypto.generateKey();
      addTearDown(key.dispose);
      final envelope = sealFor(
        owner,
        record,
        Uint8List.fromList(utf8.encode('SENTINEL_TEXT')),
        key,
      );
      expect(latin1.decode(envelope).contains('SENTINEL_TEXT'), isFalse);
    });
  });
}
