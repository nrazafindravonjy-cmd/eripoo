import 'package:flutter/material.dart';

import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../quest/presentation/content_widgets.dart';

/// Guide sections from content (interview guide, financing guide): a
/// title, then short checked items.
class GuideSectionsView extends StatelessWidget {
  const GuideSectionsView({super.key, required this.sections});

  final List<GuideSection> sections;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final section in sections) ...[
        const SizedBox(height: EripooSpacing.lg),
        Text(
          contentText(context, section.title),
          style: context.textStyles.titleMedium,
        ),
        for (final item in section.items) ...[
          const SizedBox(height: EripooSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check, size: 18),
              ),
              const SizedBox(width: EripooSpacing.sm),
              Expanded(child: Text(contentText(context, item))),
            ],
          ),
        ],
      ],
    ],
  );
}
