import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'voice_notes.dart';

/// The microphone through `record` (BSD-3): AAC, mono, 16 kHz, 32 kbit/s,
/// enough for speech and small on a phone with little space.
class SystemVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _recorder;

  AudioRecorder get _r => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission() => _r.hasPermission();

  @override
  Future<void> start(String path) => _r.start(
    const RecordConfig(bitRate: 32000, sampleRate: 16000, numChannels: 1),
    path: path,
  );

  @override
  Future<String?> stop() async {
    final path = await _r.stop();
    await _r.dispose();
    _recorder = null;
    return path;
  }

  @override
  Future<void> cancel() async {
    await _r.cancel();
    await _r.dispose();
    _recorder = null;
  }
}

/// Playback through `just_audio` (MIT), from a local file only.
class SystemVoicePlayer implements VoicePlayer {
  AudioPlayer? _player;

  @override
  Future<void> play(File file) async {
    final player = _player = AudioPlayer();
    try {
      await player.setFilePath(file.path);
      final done = player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed || !s.playing,
      );
      await player.play();
      await done;
    } finally {
      await player.dispose();
      if (identical(_player, player)) _player = null;
    }
  }

  @override
  Future<void> stop() async => _player?.stop();
}
