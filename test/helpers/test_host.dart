import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/l10n/framework_localizations.dart';
import 'package:eripoo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test surface sizes (logical pixels): an entry-level phone and a 10"
/// tablet in portrait.
const phoneSize = Size(360, 640);
const tabletSize = Size(800, 1280);

/// One combination of the design-system test matrix.
class Variant {
  const Variant(this.brightness, this.size, this.languageCode);

  final Brightness brightness;
  final Size size;
  final String languageCode;

  @override
  String toString() =>
      '${brightness.name} ${size.width.toInt()}x${size.height.toInt()} '
      '$languageCode';
}

/// Every combination of theme × screen size × language.
final allVariants = [
  for (final b in [Brightness.dark])
    for (final s in [phoneSize, tabletSize])
      for (final l in ['fr', 'en']) Variant(b, s, l),
];

/// Sets the test window size; restored automatically after the test.
void setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Hosts [child] with the Eripoo theme and localizations, outside the app
/// router.
Widget testHost(
  Widget child, {
  Brightness brightness = Brightness.dark,
  String languageCode = 'fr',
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: EripooTheme.dark(),
    locale: Locale(languageCode),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...frameworkLocalizationsDelegates,
    ],
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: app!,
    ),
    home: Scaffold(body: child),
  );
}
