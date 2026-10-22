import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../hypotheses/presentation/research_providers.dart';
import '../../trash/presentation/trash_screen.dart';
import '../application/system_voice.dart';
import '../application/voice_notes.dart';

final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => SystemVoiceRecorder(),
);

final voicePlayerProvider = Provider<VoicePlayer>((ref) => SystemVoicePlayer());

/// Where a recording waits, in clear, until it is encrypted (seconds), and
/// where a recording is decrypted for playing. Emptied at start-up.
final voiceTempDirProvider = FutureProvider<Directory>(
  (ref) async => Directory('${(await getTemporaryDirectory()).path}/voice'),
);

final voiceNotesProvider = FutureProvider<VoiceNotes>(
  (ref) async => VoiceNotes(
    media: ref.watch(mediaStoreProvider),
    trash: ref.watch(trashServiceProvider),
    tempDir: await ref.watch(voiceTempDirProvider.future),
  ),
);
