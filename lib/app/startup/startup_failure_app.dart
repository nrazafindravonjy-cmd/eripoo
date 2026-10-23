import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/framework_localizations.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../security/key_manager.dart';

/// Shown instead of the app when local data cannot be opened. Explains
/// simply, never in technical terms, and offers to start again only after
/// explicit confirmation.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.onReset,
  });

  final Object error;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: EripooTheme.dark(),
      darkTheme: EripooTheme.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...frameworkLocalizationsDelegates,
      ],
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final keysLost = error is LocalKeysLost;
          return Scaffold(
            body: SafeArea(
              child: EripooMessageView(
                icon: Icons.lock_outline,
                title: l10n.startupErrorTitle,
                message: keysLost
                    ? l10n.startupErrorKeysLost
                    : l10n.startupErrorGeneric,
                action: keysLost
                    ? EripooButton(
                        label: l10n.startupReset,
                        variant: EripooButtonVariant.secondary,
                        onPressed: () async {
                          final confirmed = await showEripooConfirmDialog(
                            context,
                            title: l10n.startupResetConfirmTitle,
                            message: l10n.startupResetConfirmBody,
                            confirmLabel: l10n.startupReset,
                            destructive: true,
                          );
                          if (confirmed) await onReset();
                        },
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
