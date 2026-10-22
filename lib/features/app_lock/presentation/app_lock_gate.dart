import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import 'app_lock_controller.dart';
import 'lock_screen.dart';

/// Covers the app with the lock screen when locked, and locks again after
/// the configured time in the background. The app below stays mounted (its
/// state is kept) but hidden from screen readers and touch.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        controller.onBackgrounded(DateTime.now());
      case AppLifecycleState.resumed:
        controller.onResumed(DateTime.now());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(appLockControllerProvider);
    final covered =
        status == AppLockStatus.loading || status == AppLockStatus.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: IgnorePointer(ignoring: covered, child: widget.child),
        ),
        if (status == AppLockStatus.loading)
          ColoredBox(color: context.colors.background),
        if (status == AppLockStatus.locked) const LockScreen(),
      ],
    );
  }
}
