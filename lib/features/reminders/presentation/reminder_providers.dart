import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reminder_platform.dart';

final reminderPlatformProvider = Provider<ReminderPlatform>(
  (ref) => AndroidReminderPlatform(),
);
