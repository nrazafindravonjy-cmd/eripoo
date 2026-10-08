import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../security/device_transfer.dart';
import '../../../services/platform/secure_window.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../account/application/device_transfer_service.dart';
import '../../account/presentation/account_messages.dart';
import '../../account/presentation/account_providers.dart';
import '../../auth/domain/auth_repository.dart';
import 'qr_widgets.dart';
import 'receive_key_screen.dart';

/// The account's devices, from the server (metadata only).
final devicesProvider = FutureProvider.autoDispose<List<RemoteDevice>>((
  ref,
) async {
  final backend = await ref.watch(accountBackendProvider.future);
  if (backend == null) return const [];
  return backend.sync.listDevices(
    currentDeviceId: ref.watch(appServicesProvider).keys.deviceId,
  );
});

/// "My devices": see them, remove a lost one, add a new one.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(devicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...devices.when(
                  loading: () => [const EripooLoadingView()],
                  error: (_, _) => [
                    Text(l10n.devicesLoadError),
                    const SizedBox(height: EripooSpacing.sm),
                    EripooButton(
                      label: l10n.actionRetry,
                      variant: EripooButtonVariant.tertiary,
                      onPressed: () => ref.invalidate(devicesProvider),
                    ),
                  ],
                  data: (list) => [
                    for (final d in list) ...[
                      _DeviceCard(d),
                      const SizedBox(height: EripooSpacing.sm),
                    ],
                  ],
                ),
                const SizedBox(height: EripooSpacing.lg),
                EripooButton(
                  label: l10n.devicesAdd,
                  icon: Icons.add_to_home_screen,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddDeviceScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard(this.device);
  final RemoteDevice device;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.devicesRemoveConfirmTitle(device.label),
      message: l10n.devicesRemoveConfirmBody,
      confirmLabel: l10n.devicesRemove,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final backend = ref.read(accountBackendProvider).value;
    if (backend == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      try {
        await backend.sync.revokeDevice(device.id);
      } on ReauthenticationRequired {
        // Removing a device needs a sign-in of less than 10 minutes.
        final email = ref.read(authUserProvider).value?.email;
        if (!context.mounted || email == null) return;
        final password = await askPassword(context);
        if (password == null) return;
        await backend.auth.signInWithEmail(email, password);
        await backend.sync.revokeDevice(device.id);
      }
      ref.invalidate(devicesProvider);
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(authMessage(l10n, e))));
    } on SyncRemoteFailure {
      messenger.showSnackBar(SnackBar(content: Text(l10n.authUnavailable)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final seen = device.lastSeenAt;
    return EripooCard(
      child: Row(
        children: [
          Icon(
            device.current ? Icons.smartphone : Icons.devices_other,
            color: device.revoked ? context.colors.textSecondary : null,
          ),
          const SizedBox(width: EripooSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.label, style: context.textStyles.titleSmall),
                if (device.current)
                  Text(l10n.devicesThis, style: context.textStyles.labelMedium)
                else if (device.revoked)
                  Text(
                    l10n.devicesRemoved,
                    style: context.textStyles.labelMedium,
                  )
                else if (seen != null)
                  Text(
                    l10n.devicesLastSeen(
                      context.formatter.dateShort(seen.toLocal()),
                    ),
                    style: context.textStyles.bodySmall,
                  ),
              ],
            ),
          ),
          if (!device.current && !device.revoked)
            EripooButton(
              label: l10n.devicesRemove,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => _remove(context, ref),
            ),
        ],
      ),
    );
  }
}

/// Asks the account password again (actions that need a recent sign-in).
Future<String?> askPassword(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _PasswordDialog(),
);

/// Owns its field: the controller lives until the dialog has finished
/// closing (disposing it when the dialog's future completed broke the
/// closing animation).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.devicesReauthTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.devicesReauthBody),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.accountPasswordLabel),
          ),
        ],
      ),
      actions: [
        EripooButton(
          label: l10n.actionCancel,
          variant: EripooButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        EripooButton(
          label: l10n.actionConfirm,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}

/// The old phone (A) of a double-QR transfer (docs/SECURITY.md §6.3):
/// confirms the owner, reads QR1, asks the code shown on the new phone,
/// then shows the sealed key for 2 minutes at most.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  String? _qr1;
  TransferOffer? _offer;
  String? _qr2;

  /// How long QR2 has been shown (counted by the timer, one tick a second).
  Duration _shown = Duration.zero;
  Timer? _tick;
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _qr2 = null;
    super.dispose();
  }

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    final authenticator = ref.read(deviceAuthenticatorProvider);
    if (await authenticator.isDeviceSecured()) {
      final ok = await authenticator.authenticate(
        reason: l10n.addDeviceIdentityReason,
        biometricOnly: false,
      );
      if (!ok) {
        setState(() => _error = l10n.addDeviceIdentityFailed);
        return;
      }
    }
    if (!mounted) return;
    final qr1 = await ref.read(qrScanProvider)(
      context,
      prefix: TransferFormat.qr1Prefix,
    );
    if (qr1 == null || !mounted) return;
    final service = ref.read(transferServiceProvider);
    if (service == null) return;
    try {
      final offer = service.readOffer(qr1);
      setState(() {
        _qr1 = qr1;
        _offer = offer;
        _error = null;
      });
    } on TransferRefused catch (e) {
      setState(() => _error = transferMessage(l10n, e.failure));
    }
  }

  Future<void> _showKey() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(transferServiceProvider);
    final owner = ref.read(authUserProvider).value?.id;
    if (service == null || owner == null || _qr1 == null) return;
    try {
      final qr2 = await service.sealForNewDevice(
        qr1: _qr1!,
        typedCode: _code.text.replaceAll(RegExp(r'\s'), ''),
        ownerId: owner,
        keys: ref.read(appServicesProvider).keys,
      );
      _shown = Duration.zero;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _shown += const Duration(seconds: 1);
        if (_shown >= TransferFormat.qr2Lifetime) {
          // Shown 2 minutes at most, then gone (no copy kept).
          _tick?.cancel();
          setState(() => _qr2 = null);
        } else {
          setState(() {});
        }
      });
      setState(() {
        _qr2 = qr2;
        _error = null;
      });
    } on TransferRefused catch (e) {
      setState(() => _error = transferMessage(l10n, e.failure));
    } on NotLinkedToAccount {
      setState(() => _error = l10n.accountMismatch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = _offer;
    final qr2 = _qr2;
    final finished = _shown >= TransferFormat.qr2Lifetime;
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.devicesAdd)),
        body: ListView(
          padding: const EdgeInsets.all(EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (qr2 != null) ...[
                    Text(
                      l10n.addDeviceKeyBody(
                        formatRemaining(TransferFormat.qr2Lifetime - _shown),
                      ),
                    ),
                    const SizedBox(height: EripooSpacing.lg),
                    Center(child: QrCodeView(data: qr2)),
                    const SizedBox(height: EripooSpacing.lg),
                    EripooButton(
                      label: l10n.actionDone,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ] else if (finished) ...[
                    Text(l10n.addDeviceDone),
                    const SizedBox(height: EripooSpacing.lg),
                    EripooButton(
                      label: l10n.actionDone,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ] else if (offer != null) ...[
                    Text(
                      l10n.addDeviceConfirm(offer.label),
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: EripooSpacing.md),
                    EripooTextField(
                      label: l10n.addDeviceCodeLabel,
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 7,
                      errorText: _error,
                    ),
                    const SizedBox(height: EripooSpacing.md),
                    EripooButton(
                      label: l10n.addDeviceShowKey,
                      icon: Icons.qr_code_2,
                      onPressed: _showKey,
                    ),
                  ] else ...[
                    Text(l10n.addDeviceWarning),
                    if (_error != null) ...[
                      const SizedBox(height: EripooSpacing.md),
                      Text(_error!),
                    ],
                    const SizedBox(height: EripooSpacing.lg),
                    EripooButton(
                      label: l10n.addDeviceScan,
                      icon: Icons.qr_code_scanner,
                      onPressed: _scan,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
