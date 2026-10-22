import 'dart:typed_data';

import 'package:qr/qr.dart';
import 'package:zxing2/qrcode.dart';

/// QR codes of the device transfer, entirely on the phone: generated with
/// `qr`, read with `zxing2` (both pure Dart). Why not a scanning library
/// such as mobile_scanner: it relies on Google ML Kit, which sends usage
/// metrics to Google and needs Play services; the codes carry key material
/// (sealed, but still), so nothing about them leaves the app.
abstract final class QrCodec {
  /// The modules of [text] (true = dark), medium error correction.
  static List<List<bool>> encode(String text) {
    final image = QrImage(
      QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    return [
      for (var r = 0; r < image.moduleCount; r++)
        [for (var c = 0; c < image.moduleCount; c++) image.isDark(r, c)],
    ];
  }

  /// Reads a QR code from a grey-level image (one byte per pixel, rows of
  /// [rowStride] bytes, e.g. the Y plane of a camera frame). Null when
  /// none is found.
  static String? decode(
    Uint8List luminance, {
    required int width,
    required int height,
    int? rowStride,
  }) {
    final stride = rowStride ?? width;
    final Int8List data;
    if (stride == width) {
      data = Int8List.view(
        luminance.buffer,
        luminance.offsetInBytes,
        width * height,
      );
    } else {
      data = Int8List(width * height);
      for (var y = 0; y < height; y++) {
        data.setRange(
          y * width,
          (y + 1) * width,
          Int8List.view(luminance.buffer, luminance.offsetInBytes + y * stride),
        );
      }
    }
    final source = _GreyLuminanceSource(data, width, height);
    try {
      return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
    } on Exception {
      return null; // NotFound, Checksum, Format: no code in this frame
    }
  }
}

/// A grey-level image as zxing reads it (its YUV source is not exported).
class _GreyLuminanceSource extends LuminanceSource {
  _GreyLuminanceSource(this._data, super.width, super.height);

  final Int8List _data;

  @override
  Int8List getRow(int y, Int8List? row) {
    final out = row != null && row.length >= width ? row : Int8List(width);
    out.setRange(0, width, _data, y * width);
    return out;
  }

  @override
  Int8List getMatrix() => _data;
}
