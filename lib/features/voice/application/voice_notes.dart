import 'dart:io';
import 'dart:typed_data';

import '../../../core/ids/ids.dart';
import '../../media/data/media_store.dart';
import '../../trash/application/trash_service.dart';

/// Records the microphone to a file (CLAUDE.md §25: offline). Behind an
/// interface so tests and other platforms can replace it.
abstract interface class VoiceRecorder {
  /// Asks for the microphone the first time; false if refused.
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// The recorded file's path, or null if nothing was recorded.
  Future<String?> stop();
  Future<void> cancel();
}

/// Plays a recorded file.
abstract interface class VoicePlayer {
  /// Completes when playing ends or is stopped.
  Future<void> play(File file);
  Future<void> stop();
}

/// Spoken answers: recorded to a temporary file in the app's private
/// cache, encrypted into the media store at once, the temporary file
/// erased. Never sent to any transcription or AI service (the user's
/// project data never goes to an external model).
class VoiceNotes {
  VoiceNotes({
    required this._media,
    required this._trash,
    required this._tempDir,
  });

  final MediaStore _media;
  final TrashService _trash;
  final Directory _tempDir;

  /// Longest answer: 3 minutes (≈ 750 KB at 32 kbit/s).
  static const maxDuration = Duration(minutes: 3);
  static const mime = 'audio/mp4';

  /// A new temporary path for a recording or a playback.
  Future<String> newTempPath() async {
    await _tempDir.create(recursive: true);
    return '${_tempDir.path}/${Ids.random()}.m4a';
  }

  /// Encrypts the recording into the media store and erases the plain
  /// file, whatever happens. Returns the media id.
  Future<String> keep(String path) async {
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const UnsupportedMedia();
      return await _media.addAudio(bytes, mime: mime);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Decrypts a recording to a temporary file for playing; null when the
  /// file is not on this phone yet. The caller deletes it after playing.
  Future<File?> openForPlaying(String mediaId) async {
    final Uint8List? bytes = await _media.read(mediaId);
    if (bytes == null) return null;
    final file = File(await newTempPath());
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Deletes a recording forever (its answer was replaced).
  Future<void> discard(String mediaId) => _trash.purgeMedia(mediaId);

  /// Plain files left by a crash or a closed app, erased at start-up.
  static Future<void> purgeTemp(Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
