import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// Text input with a visible label. Errors are shown in text, not only in
/// colour.
class EripooTextField extends StatelessWidget {
  const EripooTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.isOptional = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.footer,
  });

  /// An action shown inside the field, under the text (e.g. answering
  /// aloud): the field becomes one surface holding both ways to answer.
  final Widget? footer;

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? errorText;

  /// Appends the localized "optional" mention to the label.
  final bool isOptional;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final footer = this.footer;
    final decoration = InputDecoration(
      labelText: isOptional ? '$label (${l10n.fieldOptional})' : label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      errorText: errorText,
      errorMaxLines: 3,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
    if (footer != null) {
      final c = context.colors;
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: EripooCutBorder(
            radius: EripooRadii.lg,
            cut: 12,
            side: BorderSide(color: c.borderStrong),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EripooSpacing.xs,
            EripooSpacing.xs,
            EripooSpacing.sm,
            EripooSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                enabled: enabled,
                minLines: minLines,
                maxLines: maxLines,
                maxLength: maxLength,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                decoration: decoration.copyWith(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
              Align(alignment: AlignmentDirectional.centerEnd, child: footer),
            ],
          ),
        ),
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: isOptional ? '$label (${l10n.fieldOptional})' : label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        errorText: errorText,
        errorMaxLines: 3,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}
