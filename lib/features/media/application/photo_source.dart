import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// A photo taken or chosen by the user, in memory.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

/// Where photos come from (camera or gallery). Replaced in tests.
abstract interface class PhotoSource {
  Future<PickedPhoto?> take();
  Future<PickedPhoto?> choose();
}

/// The system camera and photo picker. They hand over a plain copy in the
/// app's cache: it is read, then deleted at once (the store keeps only the
/// encrypted version). A photo chosen from the gallery stays in the
/// gallery: that copy belongs to the user.
class SystemPhotoSource implements PhotoSource {
  SystemPhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Smaller files: faster to encrypt and to sync, far below 10 MiB.
  static const _maxSide = 1600.0;
  static const _quality = 80;

  @override
  Future<PickedPhoto?> take() => _pick(ImageSource.camera);

  @override
  Future<PickedPhoto?> choose() => _pick(ImageSource.gallery);

  Future<PickedPhoto?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return PickedPhoto(bytes, _mimeOf(file.path, file.mimeType));
    } finally {
      final copy = File(file.path);
      if (copy.existsSync()) await copy.delete();
    }
  }

  static String _mimeOf(String path, String? declared) {
    if (declared != null) return declared;
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
