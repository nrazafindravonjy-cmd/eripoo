import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'mg_material_localizations.dart';

/// Flutter ships no Material/Cupertino localizations for Malagasy (`mg`).
///
/// Material: the strings Eripoo shows or a screen reader reads are in
/// Malagasy (first draft, [MgMaterialLocalizations]); the rest falls back
/// to French. Cupertino (iOS-style widgets, not used on Android) falls
/// back to French. App strings come from `app_mg.arb`. See
/// docs/DESIGN_SYSTEM.md §5.
const fallbackLocaleForMg = Locale('fr');

class MgFallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const MgFallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'mg';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(fallbackLocaleForMg);

  @override
  bool shouldReload(MgFallbackCupertinoLocalizationsDelegate old) => false;
}

/// Delegates to register on the app, in order: app strings, Malagasy
/// fallbacks, then the global framework delegates.
const List<LocalizationsDelegate<dynamic>> frameworkLocalizationsDelegates = [
  MgMaterialLocalizationsDelegate(),
  MgFallbackCupertinoLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
