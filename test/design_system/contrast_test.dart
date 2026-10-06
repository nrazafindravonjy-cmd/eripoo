import 'package:eripoo/design_system/tokens/eripoo_colors.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const text = 4.5; // WCAG AA, normal text.
  const ui = 3.0; // WCAG AA, UI components and graphical objects.

  for (final (name, c) in [
    ('light', EripooColors.light),
    ('dark', EripooColors.dark),
  ]) {
    group('$name palette', () {
      final surfaces = {
        'background': c.background,
        'surface': c.surface,
        'surfaceMuted': c.surfaceMuted,
      };

      test('text colours are readable on every surface', () {
        for (final s in surfaces.entries) {
          expect(
            contrast(c.textPrimary, s.value),
            greaterThanOrEqualTo(text),
            reason: 'textPrimary on ${s.key}',
          );
          expect(
            contrast(c.textSecondary, s.value),
            greaterThanOrEqualTo(text),
            reason: 'textSecondary on ${s.key}',
          );
        }
      });

      test('every tone pair is readable', () {
        final tones = {
          'brand': c.brand,
          'accent': c.accent,
          'success': c.success,
          'warning': c.warning,
          'danger': c.danger,
          'info': c.info,
        };
        for (final t in tones.entries) {
          expect(
            contrast(t.value.onBase, t.value.base),
            greaterThanOrEqualTo(text),
            reason: '${t.key}.onBase on base',
          );
          expect(
            contrast(t.value.onContainer, t.value.container),
            greaterThanOrEqualTo(text),
            reason: '${t.key}.onContainer on container',
          );
        }
      });

      test('tones used as text on surfaces are readable', () {
        // Accent is excluded on purpose: it is never used as text.
        for (final tone in [c.brand, c.success, c.warning, c.danger, c.info]) {
          for (final s in surfaces.entries) {
            expect(
              contrast(tone.base, s.value),
              greaterThanOrEqualTo(text),
              reason: 'tone base on ${s.key}',
            );
          }
        }
      });

      test('control boundaries and progress are perceivable', () {
        for (final s in surfaces.entries) {
          expect(
            contrast(c.borderStrong, s.value),
            greaterThanOrEqualTo(ui),
            reason: 'borderStrong on ${s.key}',
          );
        }
        expect(
          contrast(c.brand.base, c.brand.container),
          greaterThanOrEqualTo(ui),
          reason: 'progress fill on track',
        );
      });
    });
  }
}
