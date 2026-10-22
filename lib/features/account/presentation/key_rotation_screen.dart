import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../../sync/sync_scheduler.dart';
import '../../auth/domain/auth_repository.dart';
import '../../devices/presentation/devices_screen.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/key_rotation.dart';
import 'account_messages.dart';
import 'account_providers.dart';
import 'recovery_screens.dart';

/// Null without a server.
final keyRotationProvider = Provider<KeyRotation?>((ref) {
  final backend = ref.watch(accountBackendProvider).value;
  if (backend == null) return null;
  final services = ref.watch(appServicesProvider);
  return KeyRotation(
    db: ref.watch(appDatabaseProvider),
    crypto: services.crypto,
    keyManager: services.keyManager,
    remote: backend.sync,
  );
});

final _rotationTick = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  var tick = 0;
  return db
      .tableUpdates(TableUpdateQuery.onAllTables([db.localKeyValues]))
      .map((_) => ++tick);
});

/// True while the server copies are being sealed again with a new key.
final rotationInProgressProvider = FutureProvider<bool>((ref) async {
  ref.watch(_rotationTick);
  return await ref.watch(appDatabaseProvider).readValue(KeyRotation.stageKey) !=
      null;
});

/// Rotation of the data key (docs/SECURITY.md §4.10), after a phone was
/// lost or stolen: new key, new recovery code, everything sealed again.
class KeyRotationScreen extends ConsumerStatefulWidget {
  const KeyRotationScreen({super.key});

  @override
  ConsumerState<KeyRotationScreen> createState() => _KeyRotationScreenState();
}

class _KeyRotationScreenState extends ConsumerState<KeyRotationScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final rotation = ref.read(keyRotationProvider);
    final backend = ref.read(accountBackendProvider).value;
    final user = ref.read(authUserProvider).value;
    if (rotation == null || backend == null || user == null) return;
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.rotationConfirmTitle,
      message: l10n.rotationConfirmBody,
      confirmLabel: l10n.rotationStart,
    );
    if (!ok || !mounted) return;
    // The server asks for a sign-in of less than 10 minutes: asked first,
    // before the new code is shown.
    final email = user.email;
    if (email != null) {
      final password = await askPassword(context);
      if (password == null || !mounted) return;
      try {
        await backend.auth.signInWithEmail(email, password);
      } on AuthFailure catch (e) {
        setState(() => _message = authMessage(l10n, e));
        return;
      }
    }
    if (!mounted) return;
    final code = rotation.newRecoveryCode();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecoveryCodeShowScreen(code: code),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await rotation.rotate(
        ownerId: user.id,
        keys: ref.read(appServicesProvider).keys,
        code: code,
      );
      // New data key: the app restarts to load it, then seals everything
      // again at each synchronisation.
      await ref.read(appRestartProvider)();
      return;
    } on ReauthenticationRequired {
      _message = l10n.rotationReauth;
    } on KeyVersionMismatch {
      _message = l10n.rotationMismatch;
    } on RemoteUnavailable {
      _message = l10n.rotationUnknown;
    } on RotationBusy {
      _message = l10n.rotationBusy;
    } on Object {
      _message = l10n.rotationFailed;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingChangesProvider).value ?? 1;
    final sync = ref.watch(syncStateProvider).value;
    final running = ref.watch(rotationInProgressProvider).value ?? false;
    final ready = !running && pending == 0 && sync == SyncState.saved;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rotationTitle)),
      body: ListView(
        padding: const EdgeInsets.all(EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.rotationBody),
                const SizedBox(height: EripooSpacing.lg),
                if (running)
                  Text(l10n.rotationRunning)
                else if (!ready)
                  Text(l10n.rotationNeedsSaved),
                if (_message != null) ...[
                  const SizedBox(height: EripooSpacing.md),
                  Text(
                    _message!,
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: context.colors.danger.base,
                    ),
                  ),
                ],
                const SizedBox(height: EripooSpacing.lg),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: EripooSpacing.sm),
                  Text(l10n.rotationWorking),
                ] else
                  EripooButton(
                    label: l10n.rotationStart,
                    icon: Icons.key,
                    onPressed: ready ? _start : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// This phone's key is older than the account's: opens the data again
/// with the new recovery code (or the other phone).
Future<void> openWithNewKey(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final backend = ref.read(accountBackendProvider).value;
  final owner = ref.read(authUserProvider).value?.id;
  if (backend == null || owner == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final wrap = await backend.sync.getRecoveryWrap();
    if (wrap == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockChoiceScreen(ownerId: owner, wrap: wrap),
      ),
    );
  } on RateLimited {
    messenger.showSnackBar(SnackBar(content: Text(l10n.recoveryRateLimited)));
  } on SyncRemoteFailure {
    messenger.showSnackBar(SnackBar(content: Text(l10n.authUnavailable)));
  }
}
