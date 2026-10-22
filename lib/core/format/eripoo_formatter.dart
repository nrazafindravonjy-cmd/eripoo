import '../i18n/app_language.dart';

/// Formats numbers, ariary amounts, dates and durations for mg, fr and en.
///
/// Eripoo's own implementation: `intl` has no Malagasy date or number
/// symbols (verified in intl 0.20.3), and amounts are always integers in
/// ariary (no floating point).
///
/// ⚠️ Malagasy month and weekday names and duration wording must be
/// validated by a native reviewer (decision D13, docs/DESIGN_SYSTEM.md).
class EripooFormatter {
  const EripooFormatter(this.language);

  final AppLanguage language;

  /// U+202F NARROW NO-BREAK SPACE: thousands separator (mg, fr).
  static const _narrowNbsp = ' ';

  /// U+00A0 NO-BREAK SPACE: between a number and its unit.
  static const _nbsp = ' ';

  /// U+2212 MINUS SIGN.
  static const _minus = '−';

  static const _months = {
    AppLanguage.mg: [
      'Janoary', 'Febroary', 'Martsa', 'Aprily', 'Mey', 'Jona', //
      'Jolay', 'Aogositra', 'Septambra', 'Oktobra', 'Novambra', 'Desambra',
    ],
    AppLanguage.fr: [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ],
    AppLanguage.en: [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ],
  };

  /// Monday first, as [DateTime.weekday] (1 = Monday).
  static const _weekdays = {
    AppLanguage.mg: [
      'Alatsinainy', 'Talata', 'Alarobia', 'Alakamisy', //
      'Zoma', 'Asabotsy', 'Alahady',
    ],
    AppLanguage.fr: [
      'lundi', 'mardi', 'mercredi', 'jeudi', //
      'vendredi', 'samedi', 'dimanche',
    ],
    AppLanguage.en: [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
      'Friday', 'Saturday', 'Sunday',
    ],
  };

  /// Whole number with grouping: `15 000` (mg, fr) or `15,000` (en).
  String integer(int value) {
    final digits = value.abs().toString();
    final separator = language == AppLanguage.en ? ',' : _narrowNbsp;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    return value < 0 ? '$_minus$buffer' : buffer.toString();
  }

  /// Ariary amount: `15 000 Ar` (mg, fr) or `15,000 Ar` (en).
  String money(int ariary) => '${integer(ariary)}${_nbsp}Ar';

  /// Progress fraction, never broken across lines: `4 / 12`.
  String fraction(int done, int total) =>
      '${integer(done)}$_nbsp/$_nbsp${integer(total)}';

  /// Percentage: `40 %` (mg, fr) or `40%` (en).
  String percent(int value) => language == AppLanguage.en
      ? '${integer(value)}%'
      : '${integer(value)}$_nbsp%';

  /// Rate in basis points (1 % = 100), at most one decimal, rounded:
  /// `25 %`, `33,3 %` (mg, fr) or `33.3%` (en).
  String percentBp(int bp) {
    final tenths = (bp.abs() + 5) ~/ 10;
    final whole = integer(tenths ~/ 10);
    final decimal = tenths % 10;
    final number = decimal == 0
        ? whole
        : '$whole${language == AppLanguage.en ? '.' : ','}$decimal';
    final signed = bp < 0 && tenths > 0 ? '$_minus$number' : number;
    return language == AppLanguage.en ? '$signed%' : '$signed$_nbsp%';
  }

  /// Long date: `6 Oktobra 2026`, `6 octobre 2026`, `6 October 2026`.
  String date(DateTime value) =>
      '${value.day}$_nbsp${_months[language]![value.month - 1]} ${value.year}';

  /// Numeric date, day first in every supported language: `06/10/2026`.
  String dateShort(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String weekday(DateTime value) => _weekdays[language]![value.weekday - 1];

  /// Estimated duration, rounded to the minute: `15 min`, `1 h 30 min`
  /// (`1 ora 30 min` in Malagasy).
  String duration(Duration value) {
    final totalMinutes = (value.inSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final hourUnit = language == AppLanguage.mg ? 'ora' : 'h';
    if (hours == 0) return '$minutes${_nbsp}min';
    if (minutes == 0) return '$hours$_nbsp$hourUnit';
    return '$hours$_nbsp$hourUnit $minutes${_nbsp}min';
  }
}
