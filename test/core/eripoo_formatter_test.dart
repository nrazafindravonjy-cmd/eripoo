import 'package:eripoo/core/format/eripoo_formatter.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nnbsp = ' ';
  const nbsp = ' ';
  const mg = EripooFormatter(AppLanguage.mg);
  const fr = EripooFormatter(AppLanguage.fr);
  const en = EripooFormatter(AppLanguage.en);

  group('integer and money', () {
    test('groups thousands per language', () {
      expect(fr.integer(15000), '15${nnbsp}000');
      expect(mg.integer(1250000), '1${nnbsp}250${nnbsp}000');
      expect(en.integer(1250000), '1,250,000');
    });

    test('handles small, zero and negative values', () {
      expect(fr.integer(0), '0');
      expect(fr.integer(999), '999');
      expect(fr.integer(1000), '1${nnbsp}000');
      expect(fr.integer(-2500), '−2${nnbsp}500');
    });

    test('formats ariary amounts', () {
      expect(mg.money(15000), '15${nnbsp}000${nbsp}Ar');
      expect(en.money(15000), '15,000${nbsp}Ar');
      expect(fr.money(-500), '−500${nbsp}Ar');
    });
  });

  test('fraction never breaks between its parts', () {
    expect(fr.fraction(4, 12), '4$nbsp/${nbsp}12');
    expect(fr.fraction(4, 12).contains(' '), isFalse);
  });

  test('percent', () {
    expect(fr.percent(40), '40$nbsp%');
    expect(en.percent(40), '40%');
  });

  test('percent from basis points: one decimal at most, rounded', () {
    expect(fr.percentBp(2500), '25$nbsp%');
    expect(fr.percentBp(3333), '33,3$nbsp%');
    expect(mg.percentBp(3335), '33,4$nbsp%');
    expect(en.percentBp(3333), '33.3%');
    expect(fr.percentBp(0), '0$nbsp%');
    expect(fr.percentBp(4), '0$nbsp%', reason: 'no "−0"');
    expect(fr.percentBp(-2500), '−25$nbsp%');
    expect(en.percentBp(100000), '1,000%');
  });

  group('dates', () {
    final d = DateTime(2026, 10, 6); // a Tuesday

    test('long date', () {
      expect(mg.date(d), '6${nbsp}Oktobra 2026');
      expect(fr.date(d), '6${nbsp}octobre 2026');
      expect(en.date(d), '6${nbsp}October 2026');
    });

    test('short date is day first', () {
      expect(en.dateShort(DateTime(2026, 3, 9)), '09/03/2026');
    });

    test('weekday', () {
      expect(mg.weekday(d), 'Talata');
      expect(fr.weekday(d), 'mardi');
      expect(en.weekday(DateTime(2026, 10, 11)), 'Sunday');
    });

    test('every month has a name in every language', () {
      for (final f in [mg, fr, en]) {
        for (var m = 1; m <= 12; m++) {
          expect(f.date(DateTime(2026, m, 1)), isNot(contains('null')));
        }
      }
    });
  });

  group('duration', () {
    test('minutes only', () {
      expect(fr.duration(const Duration(minutes: 15)), '15${nbsp}min');
      expect(fr.duration(Duration.zero), '0${nbsp}min');
    });

    test('hours and minutes', () {
      expect(
        fr.duration(const Duration(minutes: 90)),
        '1${nbsp}h 30${nbsp}min',
      );
      expect(
        mg.duration(const Duration(minutes: 90)),
        '1${nbsp}ora 30${nbsp}min',
      );
      expect(en.duration(const Duration(hours: 2)), '2${nbsp}h');
    });

    test('rounds to the nearest minute', () {
      expect(fr.duration(const Duration(seconds: 89)), '1${nbsp}min');
      expect(
        fr.duration(const Duration(minutes: 59, seconds: 40)),
        '1${nbsp}h',
      );
    });
  });

  test('AppLanguage.tryParse', () {
    expect(AppLanguage.tryParse('mg'), AppLanguage.mg);
    expect(AppLanguage.tryParse('fr-FR'), AppLanguage.fr);
    expect(AppLanguage.tryParse('en_GB'), AppLanguage.en);
    expect(AppLanguage.tryParse('de'), isNull);
    expect(AppLanguage.tryParse(null), isNull);
  });
}
