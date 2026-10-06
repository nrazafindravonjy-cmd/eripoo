import 'package:eripoo/security/recovery_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Damm check digit matches the published example (572 → 4)', () {
    expect(RecoveryCode.checkDigit('572'), 4);
  });

  final code = RecoveryCode.fromRandomDigits(
    List.generate(35, (i) => (i * 7 + 3) % 10),
  );

  test('a code has 36 digits, is well formed and groups as 9 × 4', () {
    expect(code.length, 36);
    expect(RecoveryCode.isWellFormed(code), isTrue);
    expect(RecoveryCode.groups(code), hasLength(9));
    expect(RecoveryCode.groups(code).every((g) => g.length == 4), isTrue);
    expect(RecoveryCode.secretPart(code), code.substring(0, 35));
  });

  test('detects every single-digit typing mistake', () {
    for (var position = 0; position < code.length; position++) {
      for (var digit = 0; digit <= 9; digit++) {
        final typed = code.replaceRange(position, position + 1, '$digit');
        if (typed == code) continue;
        expect(
          RecoveryCode.isWellFormed(typed),
          isFalse,
          reason: 'position $position digit $digit',
        );
      }
    }
  });

  test('detects every swap of two different adjacent digits', () {
    for (var i = 0; i < code.length - 1; i++) {
      if (code[i] == code[i + 1]) continue;
      final swapped = code.replaceRange(i, i + 2, '${code[i + 1]}${code[i]}');
      expect(RecoveryCode.isWellFormed(swapped), isFalse, reason: 'at $i');
    }
  });

  test('normalizes what users type', () {
    final spaced = RecoveryCode.groups(code).join(' - ');
    expect(RecoveryCode.normalize(spaced), code);
    expect(RecoveryCode.normalize('1234\n5678'), '12345678');
    expect(RecoveryCode.normalize('12a4'), isNull);
  });

  test('rejects incomplete codes and bad input', () {
    expect(RecoveryCode.isWellFormed(code.substring(0, 35)), isFalse);
    expect(() => RecoveryCode.fromRandomDigits([1, 2]), throwsArgumentError);
    expect(
      () => RecoveryCode.fromRandomDigits(List.filled(35, 10)),
      throwsArgumentError,
    );
    expect(() => RecoveryCode.secretPart('123'), throwsFormatException);
  });
}
