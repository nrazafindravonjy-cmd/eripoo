import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Malagasy strings of the Material widgets Eripoo shows or that a screen
/// reader reads (text field menu, back and close buttons, dialogs, sheets,
/// licences): docs/DESIGN_SYSTEM.md §5. FIRST DRAFT, to be reviewed by a
/// native speaker like every Malagasy string (DEVELOPMENT_PLAN P9).
///
/// Flutter ships no Malagasy Material localizations; everything not
/// listed here (date and time pickers, data tables, keyboard key names —
/// none used by Eripoo) stays French, and so do date formats.
class MgMaterialLocalizations extends MaterialLocalizationFr {
  const MgMaterialLocalizations({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  // Text field menu (visible).
  @override
  String get copyButtonLabel => 'Adikao';
  @override
  String get cutButtonLabel => 'Tapaho';
  @override
  String get pasteButtonLabel => 'Apetaho';
  @override
  String get selectAllButtonLabel => 'Fidio daholo';
  @override
  String get searchWebButtonLabel => "Karohy amin'ny Internet";
  @override
  String get shareButtonLabel => 'Zarao';
  @override
  String get lookUpButtonLabel => 'Jereo';
  @override
  String get scanTextButtonLabel => 'Hamaky soratra';

  // Buttons and labels read by a screen reader.
  @override
  String get backButtonTooltip => 'Hiverina';
  @override
  String get closeButtonTooltip => 'Hidiana';
  @override
  String get closeButtonLabel => 'Hidiana';
  @override
  String get okButtonLabel => 'OK';
  @override
  String get cancelButtonLabel => 'Hanafoana';
  @override
  String get continueButtonLabel => 'Tohizo';
  @override
  String get saveButtonLabel => 'Tehirizo';
  @override
  String get deleteButtonTooltip => 'Fafao';
  @override
  String get clearButtonTooltip => 'Fafao ny soratra';
  @override
  String get moreButtonTooltip => 'Hafa koa';
  @override
  String get showMenuTooltip => 'Asehoy ny menio';
  @override
  String get menuDismissLabel => 'Akatony ny menio';
  @override
  String get popupMenuLabel => 'Menio';
  @override
  String get openAppDrawerTooltip => 'Sokafy ny menio';
  @override
  String get drawerLabel => 'Menio';
  @override
  String get searchFieldLabel => 'Hikaroka';
  @override
  String get refreshIndicatorSemanticLabel => 'Havaozina';

  // Dialogs and sheets.
  @override
  String get alertDialogLabel => 'Fampandrenesana';
  @override
  String get dialogLabel => 'Varavarankely';
  @override
  String get bottomSheetLabel => 'Takelaka ambany';
  @override
  String get modalBarrierDismissLabel => 'Akatony';
  @override
  String get scrimLabel => 'Ambadika';
  @override
  String get scrimOnTapHintRaw => r'Akatony ny $modalRouteContentName';

  // Text field counter, read by a screen reader.
  @override
  String? get remainingTextFieldCharacterCountOne => 'Litera 1 sisa';
  @override
  String get remainingTextFieldCharacterCountOther =>
      r'Litera $remainingCount sisa';

  // Licences page (Profile).
  @override
  String get licensesPageTitle => 'Fahazoan-dalana';
  @override
  String get viewLicensesButtonLabel => 'Jereo ny fahazoan-dalana';
  @override
  String? get licensesPackageDetailTextOne => 'Fahazoan-dalana 1';
  @override
  String get licensesPackageDetailTextOther => r'Fahazoan-dalana $licenseCount';
  @override
  String? get licensesPackageDetailTextZero => 'Tsy misy fahazoan-dalana';
  @override
  String get aboutListTileTitleRaw => r'Momba ny $applicationName';
}

class MgMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const MgMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'mg';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Loads the French date and number data the formats below need,
    // synchronously like Flutter's own delegate (no extra frame).
    GlobalMaterialLocalizations.delegate.load(const Locale('fr'));
    return SynchronousFuture<MaterialLocalizations>(
      MgMaterialLocalizations(
        fullYearFormat: intl.DateFormat.y('fr'),
        compactDateFormat: intl.DateFormat.yMd('fr'),
        shortDateFormat: intl.DateFormat.yMMMd('fr'),
        mediumDateFormat: intl.DateFormat.MMMEd('fr'),
        longDateFormat: intl.DateFormat.yMMMMEEEEd('fr'),
        yearMonthFormat: intl.DateFormat.yMMMM('fr'),
        shortMonthDayFormat: intl.DateFormat.MMMd('fr'),
        decimalFormat: intl.NumberFormat.decimalPattern('fr'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'fr'),
      ),
    );
  }

  @override
  bool shouldReload(MgMaterialLocalizationsDelegate old) => false;
}
