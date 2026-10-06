import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import 'eripoo_button.dart';

/// Loading state. Announced to screen readers.
class EripooLoadingView extends StatelessWidget {
  const EripooLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message ?? AppLocalizations.of(context).stateLoading;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: EripooSpacing.lg),
            Text(text, style: context.textStyles.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// Generic message state: an icon, a title, a short explanation and an
/// optional action. Base of the empty and error states.
class EripooMessageView extends StatelessWidget {
  const EripooMessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.textStyles;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EripooSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: EripooSpacing.xxxl,
              color: iconColor ?? colors.textSecondary,
            ),
            const SizedBox(height: EripooSpacing.lg),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: EripooSpacing.sm),
              Text(
                message!,
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: EripooSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state. Reassures (data stays on the phone) and offers a retry.
class EripooErrorView extends StatelessWidget {
  const EripooErrorView({super.key, this.title, this.message, this.onRetry});

  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EripooMessageView(
      icon: Icons.error_outline,
      iconColor: context.colors.danger.base,
      title: title ?? l10n.stateErrorTitle,
      message: message ?? l10n.stateErrorBody,
      action: onRetry == null
          ? null
          : EripooButton(label: l10n.actionRetry, onPressed: onRetry),
    );
  }
}

/// Offline notice. Calm by design: being offline is normal in Eripoo.
class EripooOfflineBanner extends StatelessWidget {
  const EripooOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = AppLocalizations.of(context).stateOffline;
    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        color: colors.info.container,
        padding: const EdgeInsets.symmetric(
          horizontal: EripooSpacing.lg,
          vertical: EripooSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: colors.info.onContainer),
            const SizedBox(width: EripooSpacing.md),
            Expanded(
              child: Text(
                message,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: colors.info.onContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
