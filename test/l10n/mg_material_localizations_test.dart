// The Material strings a Malagasy user sees or hears are in Malagasy
// (first draft); French and English keep Flutter's own.
import 'package:eripoo/l10n/mg_fallback_localizations.dart';
import 'package:eripoo/l10n/mg_material_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<MaterialLocalizations> load(WidgetTester tester, Locale locale) async {
    late MaterialLocalizations result;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('mg'), Locale('fr'), Locale('en')],
        localizationsDelegates: frameworkLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            result = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Malagasy: text menu, buttons, dialogs and counters', (
    tester,
  ) async {
    final mg = await load(tester, const Locale('mg'));
    expect(mg, isA<MgMaterialLocalizations>());
    expect(mg.copyButtonLabel, 'Adikao');
    expect(mg.pasteButtonLabel, 'Apetaho');
    expect(mg.backButtonTooltip, 'Hiverina');
    expect(mg.alertDialogLabel, 'Fampandrenesana');
    expect(mg.scrimOnTapHint('Menio'), 'Akatony ny Menio');
    expect(mg.remainingTextFieldCharacterCount(3), 'Litera 3 sisa');
    expect(mg.licensesPackageDetailText(2), 'Fahazoan-dalana 2');
    // Not translated (not used by Eripoo): French, never empty.
    expect(mg.datePickerHelpText, isNotEmpty);
  });

  testWidgets('French and English are Flutter\'s own', (tester) async {
    expect((await load(tester, const Locale('fr'))).copyButtonLabel, 'Copier');
    expect((await load(tester, const Locale('en'))).copyButtonLabel, 'Copy');
  });
}
