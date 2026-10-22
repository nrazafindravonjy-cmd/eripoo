import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/usage_event.dart';
import 'usage_providers.dart';

/// On Home: counts "app opened" (once a day, if the user agreed) and sends
/// what is pending. Shows nothing.
class UsageOpenedTracker extends ConsumerStatefulWidget {
  const UsageOpenedTracker({super.key});

  @override
  ConsumerState<UsageOpenedTracker> createState() => _UsageOpenedTrackerState();
}

class _UsageOpenedTrackerState extends ConsumerState<UsageOpenedTracker> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(usageRecorderProvider)(UsageEvent.appOpened));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
