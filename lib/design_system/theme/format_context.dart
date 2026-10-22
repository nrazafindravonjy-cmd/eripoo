import 'package:flutter/widgets.dart';

import '../../core/format/eripoo_formatter.dart';
import '../../core/i18n/app_language.dart';

extension EripooFormatContext on BuildContext {
  /// Formatter for the language currently displayed.
  EripooFormatter get formatter => EripooFormatter(
    AppLanguage.tryParse(Localizations.localeOf(this).languageCode) ??
        AppLanguage.fr,
  );
}
