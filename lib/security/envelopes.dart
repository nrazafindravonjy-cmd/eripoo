import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../core/ids/uuid_bytes.dart';
import 'crypto_service.dart';

/// Binary formats of encrypted data, version 1 (docs/SECURITY.md §4.6–4.8).
///
/// Formats are **not frozen** until the first real user data
/// (DEVELOPMENT_PLAN P8). Every format starts with a version byte.
abstract final class EnvelopeFormat {
  static const v1 = 0x01;

  /// Plaintext is padded to multiples of this size before encryption.
  static const recordPadding = 256;

  static const recordContext = 'eripoo:rec:v1';
  static const mediaContext = 'eripoo:med:v1';
  static const wrapContext = 'eripoo:wrap:v1';

  /// `crypto_kdf` contexts (exactly 8 characters) and sub-key ids.
  static const recordKeyContext = 'ERPREC01';
  static const recordKeyId = 1;
  static const mediaKeyContext = 'ERPMED01';
  static const mediaKeyId = 2;
}

Uint8List _u16(int value) {
  if (value < 0 || value > 0xffff) throw RangeError.value(value);
  return Uint8List.fromList([value >> 8, value & 0xff]);
}

/// Associated data: `context || 0x00 || fixed-size fields`. Binds a
/// ciphertext to its account, its identifier and its key version.
Uint8List _associatedData(String context, List<Uint8List> fields) =>
    Uint8List.fromList([
      ...ascii.encode(context),
      0x00,
      for (final field in fields) ...field,
    ]);

/// Decoded header of an envelope.
class EnvelopeHeader {
  const EnvelopeHeader({required this.format, required this.umkVersion});

  final int format;
  final int umkVersion;

  static EnvelopeHeader read(Uint8List envelope) {
    if (envelope.length < 3) throw const DecryptionFailed();
    return EnvelopeHeader(
      format: envelope[0],
      umkVersion: (envelope[1] << 8) | envelope[2],
    );
  }
}

/// Encrypts and decrypts record payloads for synchronisation:
/// `0x01 || umk_version (2) || nonce (24) || ciphertext || tag`.
class RecordEnvelopes {
  RecordEnvelopes(this._crypto);

  final CryptoService _crypto;

  Uint8List _ad(String ownerId, String recordId, int umkVersion) =>
      _associatedData(EnvelopeFormat.recordContext, [
        uuidToBytes(ownerId),
        uuidToBytes(recordId),
        _u16(umkVersion),
      ]);

  Uint8List seal({
    required Uint8List plaintext,
    required SecureKey recordKey,
    required int umkVersion,
    required String ownerId,
    required String recordId,
  }) {
    final padded = _crypto.pad(plaintext, EnvelopeFormat.recordPadding);
    final body = _crypto.encrypt(
      padded,
      recordKey,
      ad: _ad(ownerId, recordId, umkVersion),
    );
    return Uint8List.fromList([
      EnvelopeFormat.v1,
      ..._u16(umkVersion),
      ...body,
    ]);
  }

  /// Throws [DecryptionFailed] if the envelope was not produced for this
  /// owner and record with this key, or was modified.
  Uint8List open({
    required Uint8List envelope,
    required SecureKey recordKey,
    required String ownerId,
    required String recordId,
  }) {
    final header = EnvelopeHeader.read(envelope);
    if (header.format != EnvelopeFormat.v1) throw const DecryptionFailed();
    final padded = _crypto.decrypt(
      envelope.sublist(3),
      recordKey,
      ad: _ad(ownerId, recordId, header.umkVersion),
    );
    return _crypto.unpad(padded, EnvelopeFormat.recordPadding);
  }
}

/// Encrypted media files (docs/SECURITY.md §4.7):
/// `0x01 || umk_version (2) || nonce (24) || ciphertext || tag`, in one
/// operation (files are capped at [maxPlainBytes], D15).
///
/// On this device, before any account, the owner is the nil UUID
/// ([localOwner]); uploading a file (Phase 5) seals it again for the
/// account's owner id.
class MediaEnvelopes {
  MediaEnvelopes(this._crypto);

  final CryptoService _crypto;

  static const maxPlainBytes = 10 * 1024 * 1024;
  static const localOwner = '00000000-0000-0000-0000-000000000000';

  Uint8List _ad(String ownerId, String mediaId, int umkVersion) =>
      _associatedData(EnvelopeFormat.mediaContext, [
        uuidToBytes(ownerId),
        uuidToBytes(mediaId),
        _u16(umkVersion),
      ]);

  Uint8List seal({
    required Uint8List plaintext,
    required SecureKey mediaKey,
    required int umkVersion,
    required String mediaId,
    String ownerId = localOwner,
  }) {
    if (plaintext.length > maxPlainBytes) {
      throw RangeError.range(plaintext.length, 0, maxPlainBytes);
    }
    final body = _crypto.encrypt(
      plaintext,
      mediaKey,
      ad: _ad(ownerId, mediaId, umkVersion),
    );
    return Uint8List.fromList([
      EnvelopeFormat.v1,
      ..._u16(umkVersion),
      ...body,
    ]);
  }

  /// Throws [DecryptionFailed] for another media id, owner or key, or a
  /// modified file.
  Uint8List open({
    required Uint8List envelope,
    required SecureKey mediaKey,
    required String mediaId,
    String ownerId = localOwner,
  }) {
    final header = EnvelopeHeader.read(envelope);
    if (header.format != EnvelopeFormat.v1) throw const DecryptionFailed();
    return _crypto.decrypt(
      envelope.sublist(3),
      mediaKey,
      ad: _ad(ownerId, mediaId, header.umkVersion),
    );
  }
}

/// The server copy of the data key, protected by the recovery code
/// (table `user_keys`, docs/SECURITY.md §4.8).
class RecoveryWrap {
  const RecoveryWrap({
    required this.wrapId,
    required this.umkVersion,
    required this.salt,
    required this.params,
    required this.wrapped,
  });

  final String wrapId;
  final int umkVersion;
  final Uint8List salt;
  final KdfParams params;

  /// `0x01 || nonce (24) || ciphertext || tag`.
  final Uint8List wrapped;

  static Uint8List associatedData(
    String ownerId,
    String wrapId,
    int umkVersion,
  ) => _associatedData(EnvelopeFormat.wrapContext, [
    uuidToBytes(ownerId),
    uuidToBytes(wrapId),
    _u16(umkVersion),
  ]);
}
