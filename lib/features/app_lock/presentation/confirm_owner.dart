import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../account/presentation/account_providers.dart';
import '../application/owner_check.dart';
import '../domain/app_lock_policy.dart';
import 'app_lock_controller.dart';

final ownerCheckProvider = Provider<OwnerCheck>(
  (ref) => OwnerCheck(
    ref.watch(deviceAuthenticatorProvider),
    ref.watch(appLockServiceProvider),
  ),
);

/// Confirms the owner before a sensitive action: the phone's screen lock,
/// or the Eripoo lock PIN when the phone has none. True when confirmed, or
/// when this phone has no lock at all (nothing more can be asked).
Future<bool> confirmOwner(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final check = ref.read(ownerCheckProvider);
  switch (await check.method()) {
    case OwnerCheckMethod.device:
      return check.withDevice(reason);
    case OwnerCheckMethod.appLockPin:
      if (!context.mounted) return false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _PinDialog(check: check),
      );
      return ok ?? false;
    case OwnerCheckMethod.none:
      return true;
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.check});

  final OwnerCheck check;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _wait(AppLocalizations l10n, DateTime retryAfter) {
    final remaining = retryAfter.difference(DateTime.now());
    final rounded = Duration(minutes: (remaining.inSeconds / 60).ceil());
    return l10n.lockRetryIn(context.formatter.duration(rounded));
  }

  Future<void> _submit() async {
    if (_busy || _controller.text.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await widget.check.withPin(_controller.text);
    if (!mounted) return;
    if (result is Unlocked) {
      Navigator.of(context).pop(true);
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _message = switch (result) {
        WrongPin(retryAfter: final retry?) => _wait(l10n, retry),
        LockedOut(:final retryAfter) => _wait(l10n, retryAfter),
        _ => l10n.lockWrongPin,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.ownerPinTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.ownerPinBody),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.ownerPinLabel,
              errorText: _message,
            ),
          ),
        ],
      ),
      actions: [
        EripooButton(
          label: l10n.actionCancel,
          variant: EripooButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EripooButton(
          label: l10n.actionConfirm,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
