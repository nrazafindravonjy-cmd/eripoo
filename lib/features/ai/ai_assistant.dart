import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The single place where an AI provider would plug in, so it can be
/// switched off or replaced (CLAUDE.md §24). AI is only ever occasional
/// help (transcription, translation, rephrasing, a summary), never needed
/// to move forward.
///
/// The user's private project data must never reach an external model:
/// a provider may only run on the phone, or receive text the user chose
/// to send after an explicit consent screen. None exists today.
abstract interface class AiAssistant {
  /// False when no provider is configured: callers then hide the action
  /// and the app works the same.
  bool get available;
}

/// The default and only implementation: nothing is sent anywhere.
class DisabledAiAssistant implements AiAssistant {
  const DisabledAiAssistant();

  @override
  bool get available => false;
}

final aiAssistantProvider = Provider<AiAssistant>(
  (ref) => const DisabledAiAssistant(),
);
