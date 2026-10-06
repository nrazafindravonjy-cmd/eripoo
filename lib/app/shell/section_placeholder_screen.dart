import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/generated/app_localizations.dart';

/// Honest placeholder for a top-level section that is not built yet.
///
/// It states plainly that the section is not available; it does not imitate
/// a finished screen. Each one is replaced by the real feature in its phase
/// (Home and Quest: Phase 3, Project: Phase 4, Tools: Phase 6, Profile:
/// Phase 2).
class SectionPlaceholderScreen extends StatelessWidget {
  const SectionPlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EripooMessageView(
        icon: Icons.construction_outlined,
        title: l10n.stateNotYetTitle,
        message: l10n.stateNotYetBody,
      ),
    );
  }
}
