import 'dart:typed_data';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The 16 bytes of a canonical UUID string, used as fixed-size associated
/// data in encrypted envelopes.
Uint8List uuidToBytes(String uuid) {
  if (!_uuidPattern.hasMatch(uuid)) {
    throw ArgumentError.value(uuid, 'uuid', 'not a canonical UUID');
  }
  final hex = uuid.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
