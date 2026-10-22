import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android FLAG_SECURE on the screens that show a key or a recovery code:
/// no screenshot, no screen recording or casting, blank in the recent-apps
/// preview (docs/SECURITY.md §6.5). Set by MainActivity.kt.
abstract final class SecureWindow {
  static const _channel = MethodChannel('eripoo/secure_window');

  static Future<void> set({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } on MissingPluginException {
      // Tests and platforms without the channel.
    } on PlatformException {
      // Never block the flow; the screen stays usable.
    }
  }
}

/// Keeps the window secure while [child] is shown.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    SecureWindow.set(secure: true);
  }

  @override
  void dispose() {
    SecureWindow.set(secure: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
