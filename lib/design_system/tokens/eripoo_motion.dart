import 'package:flutter/widgets.dart';

/// Motion tokens. Animations are short and subtle; all of them collapse to
/// zero when the user (system setting or Eripoo setting) asks for reduced
/// motion. The Eripoo setting is applied by overriding
/// `MediaQueryData.disableAnimations` at the app root, so this is the only
/// source of truth.
@immutable
class EripooMotion {
  const EripooMotion._({required this.reduced});

  /// Reads the reduced-motion preference from the nearest [MediaQuery].
  factory EripooMotion.of(BuildContext context) =>
      EripooMotion._(reduced: MediaQuery.disableAnimationsOf(context));

  final bool reduced;

  Duration get fast =>
      reduced ? Duration.zero : const Duration(milliseconds: 120);
  Duration get normal =>
      reduced ? Duration.zero : const Duration(milliseconds: 200);
  Duration get slow =>
      reduced ? Duration.zero : const Duration(milliseconds: 320);

  Curve get standard => Curves.easeOutCubic;
  Curve get emphasized => Curves.easeInOutCubicEmphasized;
}
