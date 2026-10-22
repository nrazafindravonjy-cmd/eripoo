// The transfer codes survive a trip through a QR image: generated here,
// "photographed" as a grey camera frame (larger, off-centre, with a row
// stride and some noise), read back exactly.
import 'dart:math';
import 'dart:typed_data';

import 'package:eripoo/features/devices/application/qr_codec.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/device_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws [modules] at [scale] px per module on a white frame of
/// [width]×[height] with a [stride], at ([left], [top]).
Uint8List frame(
  List<List<bool>> modules, {
  int scale = 6,
  int width = 640,
  int height = 480,
  int? stride,
  int left = 120,
  int top = 40,
  int noise = 0,
}) {
  final rowBytes = stride ?? width;
  final random = Random(7);
  final bytes = Uint8List(rowBytes * height)
    ..fillRange(0, rowBytes * height, 230);
  for (var r = 0; r < modules.length; r++) {
    for (var c = 0; c < modules.length; c++) {
      if (!modules[r][c]) continue;
      for (var y = 0; y < scale; y++) {
        for (var x = 0; x < scale; x++) {
          bytes[(top + r * scale + y) * rowBytes + left + c * scale + x] = 25;
        }
      }
    }
  }
  if (noise > 0) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (bytes[i] + random.nextInt(noise * 2) - noise).clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  late CryptoService crypto;
  setUpAll(() async => crypto = await CryptoService.init());

  test('QR1 and QR2 of a real transfer read back exactly', () {
    final n = TransferRequest.start(
      crypto,
      ownerId: '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a',
      deviceId: '11111111-2222-4333-8444-555555555555',
      label: 'Téléphone de la boutique',
    );
    final qr2 =
        TransferOffer.parse(
          n.qr1,
          publicKeyBytes: crypto.boxPublicKeyBytes,
        ).sealKey(
          crypto,
          ownerId: '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a',
          typedCode: n.code,
          umk: crypto.generateKey(),
          umkVersion: 1,
          senderDeviceId: '99999999-8888-4777-8666-555555555555',
        );
    for (final text in [n.qr1, qr2]) {
      final modules = QrCodec.encode(text);
      expect(
        QrCodec.decode(
          frame(modules, stride: 704, noise: 20),
          width: 640,
          height: 480,
          rowStride: 704,
        ),
        text,
      );
    }
    n.dispose();
  });

  test('a frame without a code gives nothing (no exception)', () {
    expect(QrCodec.decode(frame(const []), width: 640, height: 480), isNull);
  });
}
