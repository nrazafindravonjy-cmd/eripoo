import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../documents/presentation/pdf_export.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../media/application/photo_source.dart';
import '../../quest/presentation/journey_providers.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';

/// Section holding the business logo's media id (encrypted photo, synced
/// like every section).
const _brandSection = 'brand';

/// The business logo, decrypted, or null.
final projectLogoProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  projectId,
) async {
  final sections = await ref.watch(projectSectionsProvider(projectId).future);
  final id = sections[_brandSection]?.fields['logo'] as String?;
  if (id == null) return null;
  return ref.read(mediaStoreProvider).read(id);
});

/// The project's identity card (stage, logo, name, start date, steps),
/// with its business logo and a story-format share (Instagram or WhatsApp
/// status, Facebook, messages…): what is shared is exactly the preview,
/// with no private answer.
class ProjectCard extends ConsumerWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.steps,
    this.currentQuest,
  });

  final Project project;
  final int steps;

  /// Title of the quest in progress, if any.
  final String? currentQuest;

  Future<void> _logoMenu(BuildContext context, WidgetRef ref, bool hasLogo) {
    final l10n = AppLocalizations.of(context);
    Future<void> pick(Future<PickedPhoto?> Function() source) async {
      Navigator.of(context).pop();
      final photo = await source();
      if (photo == null) return;
      final id = await ref
          .read(mediaStoreProvider)
          .addPhoto(photo.bytes, mime: photo.mime);
      await ProjectRepository(ref.read(appDatabaseProvider)).saveSection(
        projectId: project.id,
        sectionKey: _brandSection,
        fields: {'logo': id},
      );
    }

    final photos = ref.read(photoSourceProvider);
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.projectLogoChoose),
              onTap: () => pick(photos.choose),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.projectLogoTake),
              onTap: () => pick(photos.take),
            ),
            if (hasLogo)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.projectLogoRemove),
                onTap: () async {
                  Navigator.of(context).pop();
                  await ProjectRepository(ref.read(appDatabaseProvider))
                      .saveSection(
                        projectId: project.id,
                        sectionKey: _brandSection,
                        fields: const {},
                      );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.textStyles;
    final logo = ref.watch(projectLogoProvider(project.id)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
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
                        maturityLabel(
                          l10n,
                          project.maturityStage,
                        ).toUpperCase(),
                        style: t.labelSmall?.copyWith(
                          letterSpacing: 2,
                          color: c.brand.base,
                        ),
                      ),
                    ),
                    _BusinessLogo(
                      bytes: logo,
                      size: 48,
                      label: l10n.projectLogoLabel(project.title),
                    ),
                  ],
                ),
                const SizedBox(height: EripooSpacing.xl),
                Text(project.title, style: t.headlineMedium),
                const SizedBox(height: EripooSpacing.lg),
                Text(
                  l10n.projectCardSince(
                    context.formatter.date(project.createdAt),
                  ),
                  style: t.bodySmall,
                ),
                Text(l10n.projectCardSteps(steps), style: t.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: EripooSpacing.xs),
        Wrap(
          spacing: EripooSpacing.sm,
          children: [
            EripooButton(
              label: logo == null
                  ? l10n.projectLogoAdd
                  : l10n.projectLogoChange,
              icon: Icons.add_photo_alternate_outlined,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => _logoMenu(context, ref, logo != null),
            ),
            EripooButton(
              label: l10n.projectCardShare,
              icon: Icons.ios_share,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _SharePreview(
                  project: project,
                  steps: steps,
                  currentQuest: currentQuest,
                  logo: logo,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The business logo in the signature shape, or the Eripoo mark.
class _BusinessLogo extends StatelessWidget {
  const _BusinessLogo({
    required this.bytes,
    required this.size,
    required this.label,
  });

  final Uint8List? bytes;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    if (b == null) return EripooLogo(size: size * 0.7);
    return Semantics(
      image: true,
      label: label,
      child: ClipPath(
        clipper: const ShapeBorderClipper(
          shape: EripooCutBorder(radius: 12, cut: 8),
        ),
        child: Image.memory(
          b,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
        ),
      ),
    );
  }
}

/// The story image (9:16), previewed exactly as it will be shared.
class _SharePreview extends ConsumerStatefulWidget {
  const _SharePreview({
    required this.project,
    required this.steps,
    required this.currentQuest,
    required this.logo,
  });

  final Project project;
  final int steps;
  final String? currentQuest;
  final Uint8List? logo;

  @override
  ConsumerState<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends ConsumerState<_SharePreview> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  static const _story = Size(360, 640);

  Future<void> _share() async {
    setState(() => _sharing = true);
    File? file;
    try {
      final render =
          _boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      // 1080 × 1920: the story format of Instagram, WhatsApp, Facebook.
      final image = await render.toImage(pixelRatio: 1080 / render.size.width);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await ref.read(exportDirProvider.future);
      await dir.create(recursive: true);
      file = File('${dir.path}/eripoo-story.png');
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } on Object {
      // Nothing kept: the image is rebuilt at each share.
    } finally {
      if (file != null && file.existsSync()) await file.delete();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EripooSpacing.xl,
          0,
          EripooSpacing.xl,
          EripooSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.storyPreviewTitle, style: context.textStyles.titleLarge),
            const SizedBox(height: EripooSpacing.md),
            Center(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.55,
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: SizedBox.fromSize(
                      size: _story,
                      child: _StoryCard(
                        project: widget.project,
                        steps: widget.steps,
                        currentQuest: widget.currentQuest,
                        logo: widget.logo,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: EripooSpacing.sm),
            Text(
              l10n.projectCardShareNote,
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: EripooSpacing.md),
            EripooButton(
              label: l10n.storyShare,
              icon: Icons.ios_share,
              expand: true,
              isLoading: _sharing,
              onPressed: _share,
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared story: a poster of the project in the Eripoo style.
class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.project,
    required this.steps,
    required this.currentQuest,
    required this.logo,
  });

  final Project project;
  final int steps;
  final String? currentQuest;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.textStyles;
    final quest = currentQuest;
    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          const Positioned(
            top: -60,
            right: -80,
            child: EripooOrganicShape(size: 300, seed: 21),
          ),
          const Positioned(
            bottom: 90,
            left: -70,
            child: Opacity(
              opacity: 0.6,
              child: EripooOrganicShape(size: 160, seed: 8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const EripooLogo(size: 26),
                    const SizedBox(width: EripooSpacing.sm),
                    Text(
                      maturityLabel(l10n, project.maturityStage).toUpperCase(),
                      style: t.labelSmall?.copyWith(
                        letterSpacing: 2,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
                if (logo != null) ...[
                  _BusinessLogo(
                    bytes: logo,
                    size: 72,
                    label: l10n.projectLogoLabel(project.title),
                  ),
                  const SizedBox(height: EripooSpacing.lg),
                ],
                Text(
                  project.title,
                  style: t.displaySmall?.copyWith(fontSize: 44, height: 1.05),
                ),
                const SizedBox(height: EripooSpacing.xl),
                if (quest != null) ...[
                  Text(l10n.storyCurrentQuest, style: t.labelMedium),
                  EripooHeadline('*$quest*', style: t.headlineSmall),
                  const SizedBox(height: EripooSpacing.xl),
                ],
                Row(
                  children: [
                    Text(
                      context.formatter.integer(steps),
                      style: t.displaySmall?.copyWith(color: c.brand.base),
                    ),
                    const SizedBox(width: EripooSpacing.sm),
                    Expanded(child: Text(l10n.statSteps, style: t.titleSmall)),
                  ],
                ),
                const Spacer(flex: 2),
                Text(l10n.storyFooter, style: t.labelMedium),
                Text(
                  l10n.slogan,
                  style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
