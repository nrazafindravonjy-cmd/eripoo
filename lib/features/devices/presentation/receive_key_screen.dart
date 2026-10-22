import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../security/device_transfer.dart';
import '../../../services/platform/secure_window.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../account/application/account_linker.dart';
import '../../account/presentation/account_messages.dart';
import '../../account/presentation/account_providers.dart';
import 'qr_widgets.dart';

/// "123 456": the code, easier to read and type.
String spacedCode(String code) =>
    [code.substring(0, 3), code.substring(3)].join(' ');

/// String of a remaining time, "m:ss".
String formatRemaining(Duration d) {
  final s = d.inSeconds.clamp(0, 3600);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The new phone (N) of a double-QR transfer (docs/SECURITY.md §6.3): shows
/// its one-time public key and the 6-digit code, reads the sealed key from
/// the old phone, checks it against the account's data, then restarts.
///
/// The one-time key lives in memory only and dies after 5 minutes, when
/// this screen closes, or after more than 30 s in the background.
class ReceiveKeyScreen extends ConsumerStatefulWidget {
  const ReceiveKeyScreen({super.key, required this.ownerId});
  final String ownerId;

  @override
  ConsumerState<ReceiveKeyScreen> createState() => _ReceiveKeyScreenState();
}

enum _Step { showing, checking, done }

class _ReceiveKeyScreenState extends ConsumerState<ReceiveKeyScreen> {
  TransferRequest? _request;
  ReceivedKey? _received;
  _Step _step = _Step.showing;
  String? _error;
  Timer? _tick;
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  String get _label =>
      AppLocalizations.of(context)
          .deviceDefaultName(context.formatter.dateShort(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final hidden = _hiddenAt;
        _hiddenAt = null;
        if (hidden != null &&
            DateTime.now().difference(hidden) > TransferFormat.maxBackground) {
          setState(() => _request?.dispose());
        }
      },
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request ??= _newRequest();
  }

  TransferRequest _newRequest() => TransferRequest.start(
    ref.read(appServicesProvider).crypto,
    ownerId: widget.ownerId,
    deviceId: ref.read(appServicesProvider).keys.deviceId,
    label: _label,
  );

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    _request?.dispose();
    _received?.umk.dispose();
    super.dispose();
  }

  void _restart() => setState(() {
    _request?.dispose();
    _request = _newRequest();
    _error = null;
    _step = _Step.showing;
  });

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    final qr2 = await ref.read(qrScanProvider)(
      context,
      prefix: TransferFormat.qr2Prefix,
    );
    if (qr2 == null || !mounted) return;
    try {
      _received = _request!.open(qr2);
    } on TransferRefused catch (e) {
      setState(() => _error = transferMessage(l10n, e.failure));
      return;
    }
    await _adopt();
  }

  /// Registers this phone, checks the key, stores it. Offline, the key
  /// stays in memory so the user can retry without scanning again.
  Future<void> _adopt() async {
    final l10n = AppLocalizations.of(context);
    final received = _received;
    final service = ref.read(transferServiceProvider);
    if (received == null || service == null) return;
    setState(() {
      _step = _Step.checking;
      _error = null;
    });
    String? error;
    try {
      await service.adoptReceivedKey(
        received,
        ownerId: widget.ownerId,
        deviceId: ref.read(appServicesProvider).keys.deviceId,
        deviceLabel: _label,
      );
      await rememberDeviceLabel(ref.read(appServicesProvider).database, _label);
      received.umk.dispose();
      _received = null;
      if (mounted) setState(() => _step = _Step.done);
      return;
    } on RemoteUnavailable {
      error = l10n.transferOffline;
    } on DeviceLimitReached {
      error = l10n.transferDeviceLimit;
    } on AccountMismatch {
      error = l10n.accountMismatch;
    } on TransferRefused catch (e) {
      error = transferMessage(l10n, e.failure);
      received.umk.dispose();
      _received = null;
    } on SyncRemoteFailure {
      error = l10n.authUnavailable;
    }
    if (mounted) {
      setState(() {
        _step = _Step.showing;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = _request!;
    final alive = request.isAlive;
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.receiveTitle)),
        body: ListView(
          padding: const EdgeInsets.all(EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...switch (_step) {
                    _Step.done => [
                      Text(l10n.receiveDone),
                      const SizedBox(height: EripooSpacing.lg),
                      EripooButton(
                        label: l10n.actionRestart,
                        onPressed: () => ref.read(appRestartProvider)(),
                      ),
                    ],
                    _Step.checking => [
                      const LinearProgressIndicator(),
                      const SizedBox(height: EripooSpacing.sm),
                      Text(l10n.receiveWorking),
                    ],
                    _Step.showing when _received != null => [
                      // Key in hand, server not reached: retry only.
                      if (_error != null) Text(_error!),
                      const SizedBox(height: EripooSpacing.md),
                      EripooButton(label: l10n.actionRetry, onPressed: _adopt),
                    ],
                    _Step.showing when !alive => [
                      Text(_error ?? l10n.transferExpired),
                      const SizedBox(height: EripooSpacing.md),
                      EripooButton(
                        label: l10n.actionStartAgain,
                        onPressed: _restart,
                      ),
                    ],
                    _Step.showing => [
                      Text(l10n.receiveBody),
                      const SizedBox(height: EripooSpacing.lg),
                      Center(child: QrCodeView(data: request.qr1)),
                      const SizedBox(height: EripooSpacing.md),
                      Text(
                        l10n.receiveCodeLabel,
                        textAlign: TextAlign.center,
                        style: context.textStyles.labelLarge,
                      ),
                      Text(
                        spacedCode(request.code),
                        textAlign: TextAlign.center,
                        style: context.textStyles.headlineMedium,
                      ),
                      Text(
                        l10n.receiveExpiresIn(
                          formatRemaining(request.remaining),
                        ),
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodySmall,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: EripooSpacing.md),
                        Text(_error!),
                      ],
                      const SizedBox(height: EripooSpacing.lg),
                      EripooButton(
                        label: l10n.receiveScan,
                        icon: Icons.qr_code_scanner,
                        onPressed: _scan,
                      ),
                    ],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
