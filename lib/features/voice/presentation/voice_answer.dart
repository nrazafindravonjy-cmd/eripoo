import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/voice_notes.dart';
import 'voice_providers.dart';

enum _Mode { idle, recording, saving, playing }

/// Answering an open question aloud (CLAUDE.md §25): recorded offline,
/// encrypted at once, played back, replaced or deleted. Never transcribed
/// and never sent to any AI service; the project's text stays as written.
class VoiceAnswer extends ConsumerStatefulWidget {
  const VoiceAnswer({
    super.key,
    required this.mediaId,
    required this.written,
    required this.onKept,
    required this.onDeleted,
  });

  /// The current spoken answer, if any.
  final String? mediaId;

  /// What is typed in the question's field (a recording replaces it).
  final TextEditingController written;
  final Future<void> Function(String mediaId) onKept;
  final Future<void> Function() onDeleted;

  @override
  ConsumerState<VoiceAnswer> createState() => _VoiceAnswerState();
}

class _VoiceAnswerState extends ConsumerState<VoiceAnswer> {
  _Mode _mode = _Mode.idle;
  String? _message;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // Kept for dispose, where ref can no longer be read.
  VoiceRecorder? _recorder;
  VoicePlayer? _player;
  String? _path;

  @override
  void dispose() {
    _ticker?.cancel();
    if (_mode == _Mode.recording) {
      // Leaving the question while recording drops the recording.
      final path = _path;
      unawaited(
        _recorder!
            .cancel()
            .then((_) => _deletePlain(path))
            .catchError((Object _) {}),
      );
    }
    if (_mode == _Mode.playing) unawaited(_player?.stop());
    super.dispose();
  }

  static Future<void> _deletePlain(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void _show(String? message, [_Mode mode = _Mode.idle]) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _mode = mode;
    });
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final recorder = ref.read(voiceRecorderProvider);
    _recorder = recorder;
    _show(null);
    try {
      if (!await recorder.hasPermission()) {
        return _show(l10n.voicePermissionDenied);
      }
      final notes = await ref.read(voiceNotesProvider.future);
      final path = _path = await notes.newTempPath();
      await recorder.start(path);
      if (!mounted) {
        await recorder.cancel();
        return await _deletePlain(path);
      }
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= VoiceNotes.maxDuration) _keep(atLimit: true);
      });
      _show(null, _Mode.recording);
    } on Object {
      await _deletePlain(_path);
      _show(l10n.voiceFailed);
    }
  }

  Future<void> _keep({bool atLimit = false}) async {
    if (_mode != _Mode.recording) return;
    final l10n = AppLocalizations.of(context);
    _ticker?.cancel();
    _show(null, _Mode.saving);
    final path = _path;
    try {
      final recorded = await _recorder!.stop() ?? path;
      final notes = await ref.read(voiceNotesProvider.future);
      final mediaId = await notes.keep(recorded!);
      await widget.onKept(mediaId);
      _show(atLimit ? l10n.voiceMaxReached : null);
    } on Object {
      _show(l10n.voiceFailed);
    } finally {
      // Kept or not, no plain recording stays on the phone.
      await _deletePlain(path);
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    final path = _path;
    try {
      await _recorder!.cancel();
    } on Object {
      // Nothing recorded is kept either way.
    } finally {
      await _deletePlain(path);
    }
    _show(null);
  }

  Future<void> _play() async {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(voicePlayerProvider);
    _player = player;
    File? file;
    try {
      final notes = await ref.read(voiceNotesProvider.future);
      file = await notes.openForPlaying(widget.mediaId!);
      if (file == null) return _show(l10n.voiceNotHere);
      _show(null, _Mode.playing);
      await player.play(file);
      _show(null);
    } on Object {
      _show(l10n.voicePlayFailed);
    } finally {
      await _deletePlain(file?.path);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.voiceDeleteTitle,
      message: l10n.voiceDeleteBody,
      confirmLabel: l10n.actionDelete,
      destructive: true,
    );
    if (!ok) return;
    _show(null, _Mode.saving);
    try {
      await widget.onDeleted();
      _show(null);
    } on Object {
      _show(l10n.voiceFailed);
    }
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final styles = context.textStyles;
    final busy = _mode == _Mode.saving;
    final children = <Widget>[
      if (_mode == _Mode.recording) ...[
        Row(
          children: [
            Icon(Icons.mic, color: context.colors.danger.base),
            const SizedBox(width: EripooSpacing.sm),
            Expanded(
              child: Text(
                l10n.voiceRecording(_clock(_elapsed)),
                style: styles.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: EripooSpacing.sm),
        Wrap(
          spacing: EripooSpacing.sm,
          runSpacing: EripooSpacing.xs,
          children: [
            EripooButton(
              label: l10n.voiceKeep,
              icon: Icons.stop,
              variant: EripooButtonVariant.secondary,
              onPressed: _keep,
            ),
            EripooButton(
              label: l10n.actionCancel,
              variant: EripooButtonVariant.tertiary,
              onPressed: _cancel,
            ),
          ],
        ),
      ] else if (widget.mediaId != null) ...[
        Row(
          children: [
            Icon(Icons.graphic_eq, color: context.colors.brand.base),
            const SizedBox(width: EripooSpacing.sm),
            Expanded(child: Text(l10n.voiceKept, style: styles.titleSmall)),
          ],
        ),
        const SizedBox(height: EripooSpacing.sm),
        Wrap(
          spacing: EripooSpacing.sm,
          runSpacing: EripooSpacing.xs,
          children: [
            if (_mode == _Mode.playing)
              EripooButton(
                label: l10n.voiceStopPlaying,
                icon: Icons.stop,
                variant: EripooButtonVariant.secondary,
                onPressed: () => _player?.stop(),
              )
            else
              EripooButton(
                label: l10n.voicePlay,
                icon: Icons.play_arrow,
                variant: EripooButtonVariant.secondary,
                isLoading: busy,
                onPressed: _play,
              ),
            EripooButton(
              label: l10n.voiceRecordAgain,
              icon: Icons.mic_none,
              variant: EripooButtonVariant.tertiary,
              onPressed: busy || _mode == _Mode.playing ? null : _start,
            ),
            EripooButton(
              label: l10n.voiceDelete,
              icon: Icons.delete_outline,
              variant: EripooButtonVariant.tertiary,
              onPressed: busy || _mode == _Mode.playing ? null : _delete,
            ),
          ],
        ),
      ] else ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: EripooButton(
            label: l10n.voiceAnswer,
            icon: Icons.mic_none,
            variant: EripooButtonVariant.secondary,
            isLoading: busy,
            onPressed: _start,
          ),
        ),
        ListenableBuilder(
          listenable: widget.written,
          builder: (context, _) => widget.written.text.trim().isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: EripooSpacing.xs),
                  child: Text(l10n.voiceReplaceNote, style: styles.bodySmall),
                ),
        ),
      ],
      const SizedBox(height: EripooSpacing.xs),
      Text(l10n.voiceAnswerNote, style: styles.bodySmall),
      if (_message != null) ...[
        const SizedBox(height: EripooSpacing.xs),
        Text(
          _message!,
          style: styles.bodyMedium?.copyWith(color: context.colors.danger.base),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
