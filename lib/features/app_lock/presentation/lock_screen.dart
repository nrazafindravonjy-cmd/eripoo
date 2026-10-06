import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/app_lock_policy.dart';
import '../domain/app_lock_service.dart';
import 'app_lock_controller.dart';

/// Full-screen PIN entry shown while the app is locked.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _message;
  bool _busy = false;

  AppLockController get _controller =>
      ref.read(appLockControllerProvider.notifier);

  void _type(String digit) {
    if (_busy || _pin.length >= AppLockPolicy.maxPinLength) return;
    setState(() {
      _pin += digit;
      _message = null;
    });
  }

  void _delete() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  String _waitMessage(AppLocalizations l10n, DateTime retryAfter) {
    final remaining = retryAfter.difference(DateTime.now());
    // Round up so "0 min" is never shown while still waiting.
    final rounded = Duration(minutes: (remaining.inSeconds / 60).ceil());
    return l10n.lockRetryIn(context.formatter.duration(rounded));
  }

  Future<void> _submit() async {
    if (_busy || _pin.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await _controller.unlockWithPin(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _message = switch (result) {
        Unlocked() => null,
        WrongPin(retryAfter: final retry?) => _waitMessage(l10n, retry),
        WrongPin() => l10n.lockWrongPin,
        LockedOut(:final retryAfter) => _waitMessage(l10n, retryAfter),
      };
    });
  }

  Future<void> _biometrics() async {
    final l10n = AppLocalizations.of(context);
    await _controller.unlockWithBiometrics(l10n.lockBiometricReason);
  }

  Future<void> _forgotPin() async {
    final l10n = AppLocalizations.of(context);
    final outcome = await _controller.resetWithDeviceAuthentication(
      l10n.lockForgotPinReason,
    );
    if (!mounted || outcome != PinResetOutcome.unavailable) return;
    setState(() => _message = l10n.lockForgotPinUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final text = context.textStyles;
    final biometric = ref.watch(appLockBiometricOfferedProvider).value ?? false;

    return Material(
      color: colors.background,
      child: SafeArea(
        child: ReadableColumn(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.xl),
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 40, color: colors.brand.base),
                const SizedBox(height: EripooSpacing.lg),
                Text(l10n.lockTitle, style: text.headlineSmall),
                const SizedBox(height: EripooSpacing.sm),
                Text(l10n.lockEnterPin, style: text.bodyLarge),
                const SizedBox(height: EripooSpacing.xl),
                _PinDots(count: _pin.length),
                SizedBox(
                  height: EripooSpacing.xxxl + EripooSpacing.lg,
                  child: Center(
                    child: _message == null
                        ? null
                        : Semantics(
                            liveRegion: true,
                            child: Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: colors.danger.base,
                              ),
                            ),
                          ),
                  ),
                ),
                _Keypad(
                  onDigit: _type,
                  onDelete: _delete,
                  onSubmit: _submit,
                  deleteLabel: l10n.lockDeleteDigit,
                  submitLabel: l10n.actionConfirm,
                ),
                const SizedBox(height: EripooSpacing.lg),
                if (biometric)
                  EripooButton(
                    label: l10n.lockUseBiometrics,
                    icon: Icons.fingerprint,
                    variant: EripooButtonVariant.secondary,
                    onPressed: _biometrics,
                    expand: true,
                  ),
                EripooButton(
                  label: l10n.lockForgotPin,
                  variant: EripooButtonVariant.tertiary,
                  onPressed: _forgotPin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.lockPinProgress(context.formatter.integer(count)),
      excludeSemantics: true,
      child: SizedBox(
        height: EripooSpacing.lg,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: EripooSpacing.md,
                height: EripooSpacing.md,
                margin: const EdgeInsets.symmetric(
                  horizontal: EripooSpacing.xs,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDelete,
    required this.onSubmit,
    required this.deleteLabel,
    required this.submitLabel,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;
  final String deleteLabel;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback onTap, {String? label}) => Padding(
      padding: const EdgeInsets.all(EripooSpacing.xs),
      child: SizedBox(
        width: EripooLayout.primaryActionHeight + EripooSpacing.xl,
        height: EripooLayout.primaryActionHeight + EripooSpacing.sm,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: label != null,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: onTap,
            child: child,
          ),
        ),
      ),
    );

    Widget digit(String d) =>
        key(Text(d, style: context.textStyles.headlineSmall), () => onDigit(d));

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) digit(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(
              const Icon(Icons.backspace_outlined),
              onDelete,
              label: deleteLabel,
            ),
            digit('0'),
            key(const Icon(Icons.check), onSubmit, label: submitLabel),
          ],
        ),
      ],
    );
  }
}
