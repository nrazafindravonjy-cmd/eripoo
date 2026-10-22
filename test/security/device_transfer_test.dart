// Double-QR transfer (docs/SECURITY.md §6): formats, checks, one-time key,
// expiry, and every attempt of the §6.5 table. Fictitious ids only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:eripoo/core/ids/uuid_bytes.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/device_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
const otherOwner = '0192f2a0-7c1e-7b3a-9c2d-00000000beef';
const newDevice = '11111111-2222-4333-8444-555555555555';
const oldDevice = '99999999-8888-4777-8666-555555555555';

Matcher refused(TransferFailure f) =>
    throwsA(isA<TransferRefused>().having((e) => e.failure, 'failure', f));

void main() {
  late CryptoService crypto;
  setUpAll(() async => crypto = await CryptoService.init());

  TransferRequest request({Duration Function()? elapsed, String id = owner}) =>
      TransferRequest.start(
        crypto,
        ownerId: id,
        deviceId: newDevice,
        label: 'Tablette',
        elapsed: elapsed,
      );

  TransferOffer offerOf(TransferRequest r) =>
      TransferOffer.parse(r.qr1, publicKeyBytes: crypto.boxPublicKeyBytes);

  test('the key reaches the new device intact; sizes match the spec', () {
    final umk = crypto.generateKey();
    final n = request();
    final offer = offerOf(n);
    expect(offer.deviceId, newDevice);
    expect(offer.label, 'Tablette');
    final qr2 = offer.sealKey(
      crypto,
      ownerId: owner,
      typedCode: n.code,
      umk: umk,
      umkVersion: 3,
      senderDeviceId: oldDevice,
    );
    // C = P (83) + seal overhead (48) = 131 bytes.
    final c = base64Url.decode(
      base64Url.normalize(qr2.substring(TransferFormat.qr2Prefix.length)),
    );
    expect(c.length, 131);
    final received = n.open(qr2);
    expect(received.umk.extractBytes(), umk.extractBytes());
    expect(received.umkVersion, 3);
    expect(received.senderDeviceId, oldDevice);
    expect(n.isAlive, isFalse); // one-time: the secret key is destroyed
  });

  test('QR1 carries no secret and not the account id', () {
    final n = request();
    final raw = n.qr1;
    expect(raw, startsWith('ERPT1:'));
    expect(raw.contains(owner), isFalse);
    expect(n.code, matches(RegExp(r'^\d{6}$')));
    // Same request, same code; another request, another code.
    expect(n.code, n.code);
    expect(request().code, isNot(n.code));
  });

  group('§6.5 attempts', () {
    test('a photographed QR2 cannot be opened by another device', () {
      final n = request();
      final thief = request();
      final qr2 = offerOf(n).sealKey(
        crypto,
        ownerId: owner,
        typedCode: n.code,
        umk: crypto.generateKey(),
        umkVersion: 1,
        senderDeviceId: oldDevice,
      );
      expect(() => thief.open(qr2), refused(TransferFailure.cannotOpen));
    });

    test('a QR1 changed by a third party is refused with the real code', () {
      final n = request();
      // Another key pair, same tid: the code the user reads on N no
      // longer matches.
      final attacker = request();
      final forged = TransferOffer.parse(
        attacker.qr1,
        publicKeyBytes: crypto.boxPublicKeyBytes,
      );
      expect(
        () => forged.sealKey(
          crypto,
          ownerId: owner,
          typedCode: n.code,
          umk: crypto.generateKey(),
          umkVersion: 1,
          senderDeviceId: oldDevice,
        ),
        refused(TransferFailure.wrongCode),
      );
    });

    test('a device signed in to another account is refused by both sides', () {
      final n = request(id: otherOwner);
      expect(
        () => offerOf(n).sealKey(
          crypto,
          ownerId: owner,
          typedCode: n.code,
          umk: crypto.generateKey(),
          umkVersion: 1,
          senderDeviceId: oldDevice,
        ),
        refused(TransferFailure.wrongAccount),
      );

      // A malicious "old device" sealing another account's key directly.
      final n2 = request();
      final p = Uint8List.fromList([
        1,
        ...uuidToBytes(otherOwner),
        0,
        1,
        ...List.filled(32, 7),
        ...n2.tid,
        ...uuidToBytes(oldDevice),
      ]);
      final pk = TransferOffer.parse(
        n2.qr1,
        publicKeyBytes: crypto.boxPublicKeyBytes,
      ).publicKey;
      final qr2 =
          'ERPT2:${base64Url.encode(crypto.seal(p, pk)).replaceAll('=', '')}';
      expect(() => n2.open(qr2), refused(TransferFailure.wrongAccount));
    });

    test('a key made for another transfer (wrong tid) is refused', () {
      final n = request();
      final pk = offerOf(n).publicKey;
      final p = Uint8List.fromList([
        1,
        ...uuidToBytes(owner),
        0,
        1,
        ...List.filled(32, 7),
        ...List.filled(16, 0), // not N's tid
        ...uuidToBytes(oldDevice),
      ]);
      final qr2 =
          'ERPT2:${base64Url.encode(crypto.seal(p, pk)).replaceAll('=', '')}';
      expect(() => n.open(qr2), refused(TransferFailure.wrongTransfer));
    });

    test('a wrong or mistyped code is refused', () {
      final n = request();
      final wrong = n.code == '000000' ? '000001' : '000000';
      for (final typed in [wrong, '', '12345', 'abcdef']) {
        expect(
          () => offerOf(n).sealKey(
            crypto,
            ownerId: owner,
            typedCode: typed,
            umk: crypto.generateKey(),
            umkVersion: 1,
            senderDeviceId: oldDevice,
          ),
          refused(TransferFailure.wrongCode),
          reason: typed,
        );
      }
    });
  });

  group('§6.6 expiry and one-time use (no wall clock)', () {
    test('after 5 minutes the one-time key is gone', () {
      var now = Duration.zero;
      final n = request(elapsed: () => now);
      final qr2 = offerOf(n).sealKey(
        crypto,
        ownerId: owner,
        typedCode: n.code,
        umk: crypto.generateKey(),
        umkVersion: 1,
        senderDeviceId: oldDevice,
      );
      now = TransferFormat.lifetime;
      expect(n.isAlive, isFalse);
      expect(() => n.open(qr2), refused(TransferFailure.expired));
    });

    test('cancelled (or app in background): QR2 is useless forever', () {
      final n = request();
      final qr2 = offerOf(n).sealKey(
        crypto,
        ownerId: owner,
        typedCode: n.code,
        umk: crypto.generateKey(),
        umkVersion: 1,
        senderDeviceId: oldDevice,
      );
      n.dispose();
      expect(() => n.open(qr2), refused(TransferFailure.expired));
      expect(() => n.qr1, refused(TransferFailure.expired));
    });

    test('a failed attempt also destroys the key (no retries on one key)', () {
      final n = request();
      expect(() => n.open('ERPT2:AAAA'), refused(TransferFailure.cannotOpen));
      expect(n.isAlive, isFalse);
    });
  });

  test('damaged or foreign codes are refused cleanly', () {
    int pk() => crypto.boxPublicKeyBytes;
    for (final text in ['', 'hello', 'ERPT1:', 'ERPT1:!!!', 'ERPT2:AAAA']) {
      expect(
        () => TransferOffer.parse(text, publicKeyBytes: pk()),
        refused(TransferFailure.malformed),
        reason: text,
      );
    }
    final n = request();
    final b = base64Url.decode(base64Url.normalize(n.qr1.substring(6)));
    final v2 =
        'ERPT1:${base64Url.encode([2, ...b.sublist(1)]).replaceAll('=', '')}';
    expect(
      () => TransferOffer.parse(v2, publicKeyBytes: pk()),
      refused(TransferFailure.unsupportedVersion),
    );
    final cut =
        'ERPT1:${base64Url.encode(b.sublist(0, 30)).replaceAll('=', '')}';
    expect(
      () => TransferOffer.parse(cut, publicKeyBytes: pk()),
      refused(TransferFailure.malformed),
    );
    expect(() => request().open('nope'), refused(TransferFailure.malformed));
  });

  test('labels are cut to 24 bytes without breaking a character', () {
    expect(fitLabel('  Téléphone de la boutique  '), 'Téléphone de la boutiq');
    expect(utf8.encode(fitLabel('é' * 30)).length, 24);
    expect(fitLabel('Tab'), 'Tab');
  });
}
