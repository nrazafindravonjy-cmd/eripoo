import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import 'eripoo_button.dart';
import 'eripoo_dialogs.dart';

/// Ways out of a blocking question (CLAUDE.md §5, §12). The design system
/// only reports the choice; what happens next is decided by the quest
/// engine (Phase 3), never by the widget.
enum HelpAction {
  dontKnow,
  dontUnderstand,
  showExample,
  askHelp,
  skipForNow,
  comeBackLater,
}

/// "Need help?" button opening the help options. Always shown on an
/// important interaction, so the user is never stuck.
class EripooHelpButton extends StatelessWidget {
  const EripooHelpButton({
    super.key,
    required this.onSelected,
    this.actions = HelpAction.values,
  });

  final ValueChanged<HelpAction> onSelected;

  /// Options offered, in display order (content may hide irrelevant ones).
  final List<HelpAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EripooButton(
      label: l10n.helpMenu,
      icon: Icons.help_outline,
      variant: EripooButtonVariant.tertiary,
      onPressed: () async {
        final choice = await showEripooSheet<HelpAction>(
          context,
          builder: (context) => _HelpOptions(actions: actions),
        );
        if (choice != null) onSelected(choice);
      },
    );
  }
}

class _HelpOptions extends StatelessWidget {
  const _HelpOptions({required this.actions});

  final List<HelpAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: EripooSpacing.sm),
          child: Text(l10n.helpMenu, style: context.textStyles.titleLarge),
        ),
        for (final action in actions)
          ListTile(
            minTileHeight: EripooLayout.primaryActionHeight,
            contentPadding: EdgeInsets.zero,
            leading: Icon(helpActionIcon(action), color: colors.brand.base),
            title: Text(
              helpActionLabel(l10n, action),
              style: context.textStyles.bodyLarge,
            ),
            onTap: () => Navigator.of(context).pop(action),
          ),
      ],
    );
  }
}

String helpActionLabel(AppLocalizations l10n, HelpAction action) =>
    switch (action) {
      HelpAction.dontKnow => l10n.helpDontKnow,
      HelpAction.dontUnderstand => l10n.helpDontUnderstand,
      HelpAction.showExample => l10n.helpShowExample,
      HelpAction.askHelp => l10n.helpAskHelp,
      HelpAction.skipForNow => l10n.helpSkipForNow,
      HelpAction.comeBackLater => l10n.helpComeBackLater,
    };

IconData helpActionIcon(HelpAction action) => switch (action) {
  HelpAction.dontKnow => Icons.question_mark,
  HelpAction.dontUnderstand => Icons.chat_bubble_outline,
  HelpAction.showExample => Icons.lightbulb_outline,
  HelpAction.askHelp => Icons.support_outlined,
  HelpAction.skipForNow => Icons.skip_next_outlined,
  HelpAction.comeBackLater => Icons.schedule,
};
