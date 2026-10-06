import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material/Cupertino localizations for Malagasy (`mg`).
///
/// Until reviewed Malagasy translations of the framework strings exist,
/// framework widgets (date pickers, tooltips, a11y labels) fall back to
/// French when the app locale is `mg`. App strings are unaffected: they come
/// from `app_mg.arb`. See docs/ARCHITECTURE.md, section i18n.
const fallbackLocaleForMg = Locale('fr');

class MgFallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const MgFallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'mg';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(fallbackLocaleForMg);

  @override
  bool shouldReload(MgFallbackMaterialLocalizationsDelegate old) => false;
}

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
  MgFallbackMaterialLocalizationsDelegate(),
  MgFallbackCupertinoLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
