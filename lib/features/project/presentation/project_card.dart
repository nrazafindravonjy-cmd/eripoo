import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../documents/presentation/pdf_export.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../domain/project.dart';

/// The project's identity card: name, stage, start date and steps done,
/// on a dark card in the signature shape. It can be shared as an image:
/// what is shared is exactly the card on screen, with no private answer.
class ProjectCard extends ConsumerStatefulWidget {
  const ProjectCard({super.key, required this.project, required this.steps});

  final Project project;
  final int steps;

  @override
  ConsumerState<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<ProjectCard> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    File? file;
    try {
      final render =
          _boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await ref.read(exportDirProvider.future);
      await dir.create(recursive: true);
      file = File('${dir.path}/eripoo-card.png');
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } on Object {
      // Nothing to keep: the image is rebuilt at each share.
    } finally {
      if (file != null && file.existsSync()) await file.delete();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.textStyles;
    final p = widget.project;
    final card = RepaintBoundary(
      key: _boundary,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surfaceMuted,
          shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 30),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EripooSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      maturityLabel(l10n, p.maturityStage).toUpperCase(),
                      style: t.labelSmall?.copyWith(
                        letterSpacing: 2,
                        color: c.brand.base,
                      ),
                    ),
                  ),
                  const EripooLogo(size: 32),
                ],
              ),
              const SizedBox(height: EripooSpacing.xl),
              Text(p.title, style: t.headlineMedium),
              const SizedBox(height: EripooSpacing.lg),
              Text(
                l10n.projectCardSince(context.formatter.date(p.createdAt)),
                style: t.bodySmall,
              ),
              Text(l10n.projectCardSteps(widget.steps), style: t.bodySmall),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: EripooSpacing.sm),
        Text(l10n.projectCardShareNote, style: t.bodySmall),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: EripooButton(
            label: l10n.projectCardShare,
            icon: Icons.ios_share,
            variant: EripooButtonVariant.tertiary,
            isLoading: _sharing,
            onPressed: _share,
          ),
        ),
      ],
    );
  }
}
