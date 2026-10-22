import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../core/ids/uuid_bytes.dart';
import 'crypto_service.dart';

/// Why a device transfer step is refused (docs/SECURITY.md §6.4–6.6).
enum TransferFailure {
  /// Not an Eripoo transfer code, or damaged.
  malformed,

  /// A newer format than this app understands.
  unsupportedVersion,

  /// The other device is signed in to another account.
  wrongAccount,

  /// The code typed on the old device is not the one on the new device.
  wrongCode,

  /// The key was made for another transfer (its QR1 was not ours).
  wrongTransfer,

  /// The new device's one-time key is gone (time out, cancelled, closed).
  expired,

  /// The second code cannot be opened with this device's one-time key.
  cannotOpen,

  /// The received key does not open the account's existing data.
  keyDoesNotMatch,
}

class TransferRefused implements Exception {
  const TransferRefused(this.failure);
  final TransferFailure failure;
}

/// Formats v1 (docs/SECURITY.md §6.3).
abstract final class TransferFormat {
  static const version = 0x01;
  static const qr1Prefix = 'ERPT1:';
  static const qr2Prefix = 'ERPT2:';
  static const context = 'eripoo:xfer:v1';
  static const tidBytes = 16;
  static const accountHintBytes = 8;
  static const maxLabelBytes = 24;

  /// The new device's one-time key lives at most this long (monotonic
  /// time, never the phone's clock, which is often wrong).
  static const lifetime = Duration(minutes: 5);

  /// The old device shows the key at most this long.
  static const qr2Lifetime = Duration(minutes: 2);

  /// Leaving the app longer than this destroys the one-time key.
  static const maxBackground = Duration(seconds: 30);

  /// `0x01 || owner (16) || umk_version (2) || UMK (32) || tid (16) ||
  /// sender device (16)` = 83 bytes.
  static const payloadBytes = 1 + 16 + 2 + 32 + 16 + 16;
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _unb64(String text) {
  final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

String _uuidOf(List<int> b) {
  String hex(int from, int to) =>
      [for (final x in b.sublist(from, to)) x.toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Hint of the account in QR1: 8 bytes of BLAKE2b of the owner id, so the
/// id itself is never shown.
/// (libsodium's shortest BLAKE2b output is 16 bytes: the first 8 are kept.)
Uint8List transferAccountHint(CryptoService crypto, String ownerId) =>
    Uint8List.fromList(
      crypto
          .hash(
            Uint8List.fromList(
              utf8.encode('${TransferFormat.context}:$ownerId'),
            ),
            length: 16,
          )
          .sublist(0, TransferFormat.accountHintBytes),
    );

/// The 6 digits shown on the new device and typed on the old one:
/// `generichash("eripoo:xfer:v1" || tid || pk_N)`, first 8 bytes modulo
/// 10⁶ (bias below 10⁻¹³).
String verificationCode(CryptoService crypto, Uint8List tid, Uint8List pk) {
  final digest = crypto.hash(
    Uint8List.fromList([
      ...ascii.encode(TransferFormat.context),
      ...tid,
      ...pk,
    ]),
  );
  var value = BigInt.zero;
  for (final b in digest.sublist(0, 8)) {
    value = (value << 8) | BigInt.from(b);
  }
  return (value % BigInt.from(1000000)).toString().padLeft(6, '0');
}

/// A label cut to [TransferFormat.maxLabelBytes] UTF-8 bytes without
/// breaking a character.
String fitLabel(String label) {
  var out = '';
  for (final rune in label.trim().runes) {
    final next = out + String.fromCharCode(rune);
    if (utf8.encode(next).length > TransferFormat.maxLabelBytes) break;
    out = next;
  }
  return out;
}

/// The new device's side (N): a one-time key pair in memory only, shown as
/// QR1 with a 6-digit code; opens QR2 at most once.
class TransferRequest {
  TransferRequest._(
    this._crypto,
    this._keys,
    this.tid,
    this.deviceId,
    this.ownerId,
    this.label,
    this._clock,
  ) : _started = _clock();

  /// [elapsed] measures monotonic time (a stopwatch), never the clock.
  factory TransferRequest.start(
    CryptoService crypto, {
    required String ownerId,
    required String deviceId,
    required String label,
    Duration Function()? elapsed,
  }) {
    final stopwatch = Stopwatch()..start();
    return TransferRequest._(
      crypto,
      crypto.boxKeyPair(),
      crypto.randomBytes(TransferFormat.tidBytes),
      deviceId,
      ownerId,
      fitLabel(label),
      elapsed ?? () => stopwatch.elapsed,
    );
  }

  final CryptoService _crypto;
  KeyPair? _keys;
  final Uint8List tid;
  final String deviceId;
  final String ownerId;
  final String label;
  final Duration Function() _clock;
  final Duration _started;

  bool get isAlive =>
      _keys != null && _clock() - _started < TransferFormat.lifetime;

  /// Time left before the one-time key dies by itself.
  Duration get remaining {
    final left = TransferFormat.lifetime - (_clock() - _started);
    return left.isNegative || _keys == null ? Duration.zero : left;
  }

  Uint8List get _publicKey =>
      (_keys ?? (throw const TransferRefused(TransferFailure.expired)))
          .publicKey;

  String get qr1 =>
      TransferFormat.qr1Prefix +
      _b64([
        TransferFormat.version,
        ...tid,
        ..._publicKey,
        ...uuidToBytes(deviceId),
        ...transferAccountHint(_crypto, ownerId),
        ...utf8.encode(label),
      ]);

  String get code => verificationCode(_crypto, tid, _publicKey);

  /// Opens QR2 shown by the old device. The one-time key is destroyed
  /// afterwards, whatever the result: a code can be opened only once.
  ReceivedKey open(String qr2) {
    try {
      if (!isAlive) throw const TransferRefused(TransferFailure.expired);
      if (!qr2.startsWith(TransferFormat.qr2Prefix)) {
        throw const TransferRefused(TransferFailure.malformed);
      }
      final Uint8List cipher;
      try {
        cipher = _unb64(qr2.substring(TransferFormat.qr2Prefix.length));
      } on FormatException {
        throw const TransferRefused(TransferFailure.malformed);
      }
      final Uint8List p;
      try {
        p = _crypto.sealOpen(cipher, _keys!);
      } on DecryptionFailed {
        throw const TransferRefused(TransferFailure.cannotOpen);
      }
      try {
        if (p.length != TransferFormat.payloadBytes) {
          throw const TransferRefused(TransferFailure.malformed);
        }
        if (p[0] != TransferFormat.version) {
          throw const TransferRefused(TransferFailure.unsupportedVersion);
        }
        if (!_same(p.sublist(1, 17), uuidToBytes(ownerId))) {
          throw const TransferRefused(TransferFailure.wrongAccount);
        }
        if (!_same(p.sublist(51, 67), tid)) {
          throw const TransferRefused(TransferFailure.wrongTransfer);
        }
        return ReceivedKey(
          umk: _crypto.keyFromBytes(Uint8List.fromList(p.sublist(19, 51))),
          umkVersion: (p[17] << 8) | p[18],
          senderDeviceId: _uuidOf(p.sublist(67, 83)),
        );
      } finally {
        p.fillRange(0, p.length, 0);
      }
    } finally {
      dispose();
    }
  }

  /// Destroys the one-time secret key (cancel, success, background).
  void dispose() {
    final keys = _keys;
    _keys = null;
    keys?.secretKey.dispose();
  }
}

/// The data key received by the new device (to verify, then store).
class ReceivedKey {
  const ReceivedKey({
    required this.umk,
    required this.umkVersion,
    required this.senderDeviceId,
  });

  final SecureKey umk;
  final int umkVersion;
  final String senderDeviceId;
}

/// QR1 read by the old device (A).
class TransferOffer {
  const TransferOffer._({
    required this.tid,
    required this.publicKey,
    required this.deviceId,
    required this.accountHint,
    required this.label,
  });

  final Uint8List tid;
  final Uint8List publicKey;
  final String deviceId;
  final Uint8List accountHint;
  final String label;

  static TransferOffer parse(String qr1, {required int publicKeyBytes}) {
    if (!qr1.startsWith(TransferFormat.qr1Prefix)) {
      throw const TransferRefused(TransferFailure.malformed);
    }
    final Uint8List b;
    try {
      b = _unb64(qr1.substring(TransferFormat.qr1Prefix.length));
    } on FormatException {
      throw const TransferRefused(TransferFailure.malformed);
    }
    final fixed =
        1 +
        TransferFormat.tidBytes +
        publicKeyBytes +
        16 +
        TransferFormat.accountHintBytes;
    if (b.isEmpty) throw const TransferRefused(TransferFailure.malformed);
    if (b[0] != TransferFormat.version) {
      throw const TransferRefused(TransferFailure.unsupportedVersion);
    }
    if (b.length < fixed || b.length > fixed + TransferFormat.maxLabelBytes) {
      throw const TransferRefused(TransferFailure.malformed);
    }
    var at = 1;
    Uint8List take(int n) {
      final part = Uint8List.fromList(b.sublist(at, at + n));
      at += n;
      return part;
    }

    final tid = take(TransferFormat.tidBytes);
    final pk = take(publicKeyBytes);
    final device = _uuidOf(take(16));
    final hint = take(TransferFormat.accountHintBytes);
    final String label;
    try {
      label = utf8.decode(b.sublist(at));
    } on FormatException {
      throw const TransferRefused(TransferFailure.malformed);
    }
    return TransferOffer._(
      tid: tid,
      publicKey: pk,
      deviceId: device,
      accountHint: hint,
      label: label,
    );
  }

  /// QR2 for the new device: the data key sealed to its one-time public
  /// key. Refused unless both phones use the same account and the user
  /// typed the code shown on the new device.
  String sealKey(
    CryptoService crypto, {
    required String ownerId,
    required String typedCode,
    required SecureKey umk,
    required int umkVersion,
    required String senderDeviceId,
  }) {
    if (!_same(accountHint, transferAccountHint(crypto, ownerId))) {
      throw const TransferRefused(TransferFailure.wrongAccount);
    }
    final expected = verificationCode(crypto, tid, publicKey);
    if (!_same(utf8.encode(typedCode.trim()), utf8.encode(expected))) {
      throw const TransferRefused(TransferFailure.wrongCode);
    }
    final key = umk.extractBytes();
    final p = Uint8List.fromList([
      TransferFormat.version,
      ...uuidToBytes(ownerId),
      umkVersion >> 8,
      umkVersion & 0xff,
      ...key,
      ...tid,
      ...uuidToBytes(senderDeviceId),
    ]);
    key.fillRange(0, key.length, 0);
    try {
      return TransferFormat.qr2Prefix + _b64(crypto.seal(p, publicKey));
    } finally {
      p.fillRange(0, p.length, 0);
    }
  }
}
