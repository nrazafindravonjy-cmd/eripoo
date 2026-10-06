import 'package:flutter/widgets.dart';

import '../tokens/eripoo_dimens.dart';

/// Width classes (Material guidance). Layout decisions depend on the
/// available width only, never on the device type or orientation: on
/// Android 16+ large screens the system may ignore the portrait lock, so a
/// tablet can end up in landscape (docs/DESIGN_SYSTEM.md).
enum WindowSize {
  /// < 600 dp: phones.
  compact,

  /// 600–839 dp: tablets in portrait.
  medium,

  /// ≥ 840 dp: large tablets, landscape.
  expanded;

  static WindowSize fromWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    return expanded;
  }

  bool get isCompact => this == compact;

  double get gutter =>
      isCompact ? EripooLayout.gutterCompact : EripooLayout.gutterMedium;
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize =>
      WindowSize.fromWidth(MediaQuery.sizeOf(this).width);
}
