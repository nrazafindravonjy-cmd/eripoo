import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';
import 'staff_api.dart';

String staffErrorText(AppLocalizations l, Object error) =>
    switch (error is StaffException ? error.error : StaffError.other) {
      StaffError.conflict => l.errorConflict,
      StaffError.mfaRequired => l.errorMfa,
      StaffError.notStaff => l.errorNotStaff,
      StaffError.invalid => l.errorInvalid,
      StaffError.other => l.errorGeneric,
    };

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
