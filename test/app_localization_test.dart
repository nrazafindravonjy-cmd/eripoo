import 'package:eripoo/app/app.dart';
import 'package:eripoo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports exactly fr, mg and en', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'fr', 'mg', 'en'},
    );
  });

  for (final code in ['fr', 'mg', 'en']) {
    testWidgets('renders identity and framework strings in "$code"', (
      tester,
    ) async {
      await tester.pumpWidget(EripooApp(locale: Locale(code)));
      await tester.pumpAndSettle();

      expect(find.text('Eripoo'), findsOneWidget);
      expect(find.text("Mihary ho an'ny ho avy."), findsOneWidget);

      final context = tester.element(find.text('Eripoo'));
      expect(AppLocalizations.of(context).localeName, code);
      // Framework strings must resolve for every locale; mg falls back to fr.
      final material = MaterialLocalizations.of(context);
      expect(material.okButtonLabel, code == 'en' ? 'OK' : isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
