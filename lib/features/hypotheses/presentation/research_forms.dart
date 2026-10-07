import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/research.dart';
import 'research_providers.dart';

/// Opens a sheet for a new action: a message about the previous one is
/// removed first, so it can never cover the sheet's buttons.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  return showEripooSheet<T>(context, builder: builder);
}

/// One text field of a form sheet.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.helper,
    this.initial,
    this.maxLines = 1,
    this.maxLength,
    this.optional = false,
    this.number = false,
  });

  final String key;
  final String label;
  final String? helper;
  final String? initial;
  final int maxLines;
  final int? maxLength;
  final bool optional;

  /// Digits only.
  final bool number;
}

/// A bottom sheet with text fields; resolves to the trimmed values, or null
/// when dismissed. Required fields must not be empty.
Future<Map<String, String>?> showFieldsSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String? note,
  String? submitLabel,
}) => showFormSheet<Map<String, String>>(
  context,
  builder: (_) => _FieldsSheet(
    title: title,
    fields: fields,
    note: note,
    submitLabel: submitLabel,
  ),
);

class _FieldsSheet extends StatefulWidget {
  const _FieldsSheet({
    required this.title,
    required this.fields,
    this.note,
    this.submitLabel,
  });

  final String title;
  final List<FieldSpec> fields;
  final String? note;
  final String? submitLabel;

  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
  late final _controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial ?? ''),
  };
  final _missing = <String>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = {
      for (final e in _controllers.entries) e.key: e.value.text.trim(),
    };
    setState(() {
      _missing
        ..clear()
        ..addAll([
          for (final f in widget.fields)
            if (!f.optional && values[f.key]!.isEmpty) f.key,
        ]);
    });
    if (_missing.isEmpty) Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: context.textStyles.titleLarge),
        if (widget.note != null) ...[
          const SizedBox(height: EripooSpacing.sm),
          Text(widget.note!, style: context.textStyles.bodyMedium),
        ],
        for (final f in widget.fields) ...[
          const SizedBox(height: EripooSpacing.md),
          EripooTextField(
            label: f.label,
            helper: f.helper,
            controller: _controllers[f.key],
            minLines: f.maxLines > 1 ? 2 : 1,
            maxLines: f.maxLines,
            maxLength: f.maxLength,
            isOptional: f.optional,
            keyboardType: f.number ? TextInputType.number : null,
            errorText: _missing.contains(f.key) ? l10n.guardInvalidText : null,
          ),
        ],
        const SizedBox(height: EripooSpacing.lg),
        EripooButton(
          label: widget.submitLabel ?? l10n.actionSave,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// A list of options in a sheet; resolves to the chosen value.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
}) => showFormSheet<T>(
  context,
  builder: (context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: context.textStyles.titleLarge),
      const SizedBox(height: EripooSpacing.sm),
      for (final (value, label) in options)
        ListTile(
          title: Text(label),
          onTap: () => Navigator.of(context).pop(value),
        ),
    ],
  ),
);

/// 1 to 5, as a row of choice chips.
class ConfidencePicker extends StatelessWidget {
  const ConfidencePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textStyles.labelLarge),
        const SizedBox(height: EripooSpacing.xs),
        Wrap(
          spacing: EripooSpacing.sm,
          children: [
            for (var v = 1; v <= 5; v++)
              ChoiceChip(
                label: Text(context.formatter.integer(v)),
                selected: v == value,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Adds a piece of evidence to [subject]: note, photo, link, number or
/// sale. Photos are encrypted at once (docs/SECURITY.md §4.7).
Future<void> addEvidenceFlow(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required EvidenceSubject subject,
  required String subjectId,
}) async {
  final l10n = AppLocalizations.of(context);
  final kind = await showChoiceSheet<EvidenceKind>(
    context,
    title: l10n.evidenceAdd,
    options: [
      for (final k in EvidenceKind.values) (k, evidenceKindLabel(l10n, k)),
    ],
  );
  if (kind == null || !context.mounted) return;
  final research = ref.read(researchServiceProvider);

  Future<void> add({
    String? body,
    String? mediaId,
    double? numberValue,
    int? amountMga,
  }) async {
    await runGuarded(
      context,
      () => research.addEvidence(
        projectId: projectId,
        subject: subject,
        subjectId: subjectId,
        kind: kind,
        body: body,
        mediaId: mediaId,
        numberValue: numberValue,
        amountMga: amountMga,
      ),
    );
  }

  switch (kind) {
    case EvidenceKind.photo:
      final fromCamera = await showChoiceSheet<bool>(
        context,
        title: l10n.evidencePhotoPrivacy,
        options: [
          (true, l10n.evidencePhotoTake),
          (false, l10n.evidencePhotoChoose),
        ],
      );
      if (fromCamera == null || !context.mounted) return;
      final source = ref.read(photoSourceProvider);
      final photo = fromCamera ? await source.take() : await source.choose();
      if (photo == null || !context.mounted) return;
      String? mediaId;
      final stored = await runGuarded(context, () async {
        mediaId = await ref
            .read(mediaStoreProvider)
            .addPhoto(photo.bytes, mime: photo.mime);
      });
      if (stored && context.mounted) await add(mediaId: mediaId);
    case EvidenceKind.note || EvidenceKind.link:
      final values = await showFieldsSheet(
        context,
        title: evidenceKindLabel(l10n, kind),
        fields: [
          FieldSpec(
            'text',
            kind == EvidenceKind.note
                ? l10n.evidenceNoteLabel
                : l10n.evidenceLinkLabel,
            maxLines: kind == EvidenceKind.note ? 5 : 1,
            maxLength: kind == EvidenceKind.note
                ? FieldNoteRules.maxNotesLength
                : FieldNoteRules.maxLinkLength,
          ),
        ],
      );
      if (values != null && context.mounted) await add(body: values['text']);
    case EvidenceKind.number:
      final values = await showFieldsSheet(
        context,
        title: evidenceKindLabel(l10n, kind),
        fields: [FieldSpec('n', l10n.evidenceNumberLabel, number: true)],
      );
      if (values == null || !context.mounted) return;
      await add(
        numberValue: double.tryParse(values['n']!.replaceAll(',', '.')),
      );
    case EvidenceKind.sale:
      final values = await showFieldsSheet(
        context,
        title: evidenceKindLabel(l10n, kind),
        fields: [FieldSpec('amount', l10n.evidenceSaleLabel, number: true)],
      );
      if (values == null || !context.mounted) return;
      await add(
        amountMga: int.tryParse(
          values['amount']!.replaceAll(RegExp(r'[\s.]'), ''),
        ),
      );
  }
}

/// The evidence of one subject, with a button to add more.
class EvidenceList extends ConsumerWidget {
  const EvidenceList({
    super.key,
    required this.evidences,
    required this.projectId,
    required this.subject,
    required this.subjectId,
  });

  final List<Evidence> evidences;
  final String projectId;
  final EvidenceSubject subject;
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in evidences)
          Padding(
            padding: const EdgeInsets.only(bottom: EripooSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_iconOf(e.kind), size: 18),
                const SizedBox(width: EripooSpacing.sm),
                Expanded(child: _EvidenceBody(e)),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: EripooButton(
            label: l10n.evidenceAdd,
            icon: Icons.add,
            variant: EripooButtonVariant.tertiary,
            onPressed: () => addEvidenceFlow(
              context,
              ref,
              projectId: projectId,
              subject: subject,
              subjectId: subjectId,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _iconOf(EvidenceKind kind) => switch (kind) {
    EvidenceKind.note => Icons.notes,
    EvidenceKind.photo => Icons.photo_outlined,
    EvidenceKind.link => Icons.link,
    EvidenceKind.number => Icons.numbers,
    EvidenceKind.sale => Icons.payments_outlined,
  };
}

class _EvidenceBody extends StatelessWidget {
  const _EvidenceBody(this.evidence);
  final Evidence evidence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    return switch (evidence.kind) {
      EvidenceKind.note || EvidenceKind.link => Text(evidence.body ?? ''),
      EvidenceKind.number => Text(
        evidence.numberValue == null
            ? ''
            : evidence.numberValue == evidence.numberValue!.roundToDouble()
            ? f.integer(evidence.numberValue!.round())
            : evidence.numberValue.toString(),
      ),
      EvidenceKind.sale => Text(
        l10n.evidenceSale(f.money(evidence.amountMga ?? 0)),
      ),
      EvidenceKind.photo => MediaThumbnail(mediaId: evidence.mediaId),
    };
  }
}

/// A photo decrypted in memory for display only.
class MediaThumbnail extends ConsumerStatefulWidget {
  const MediaThumbnail({super.key, required this.mediaId});
  final String? mediaId;

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  late final Future<Uint8List?> _bytes = _load();

  Future<Uint8List?> _load() async {
    final id = widget.mediaId;
    if (id == null) return null;
    try {
      return await ref.read(mediaStoreProvider).read(id);
    } on Object {
      return null; // shown as unreadable, never as a crash
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Text(
            l10n.evidencePhotoMissing,
            style: context.textStyles.bodySmall,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(EripooRadii.md),
          child: Image.memory(
            bytes,
            height: 160,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            semanticLabel: l10n.evidenceKindPhoto,
            errorBuilder: (_, _, _) => Text(l10n.evidencePhotoUnreadable),
          ),
        );
      },
    );
  }
}
