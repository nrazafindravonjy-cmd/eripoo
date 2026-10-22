import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../../sync/sync_cycle.dart';
import '../../../sync/sync_scheduler.dart';
import '../../app_lock/presentation/confirm_owner.dart';
import '../../auth/domain/auth_repository.dart';
import '../../devices/presentation/devices_screen.dart';
import '../../documents/presentation/document_screens.dart';
import '../../documents/presentation/documents_providers.dart';
import '../../documents/presentation/pdf_export.dart';
import '../../latency/presentation/latency_screen.dart';
import '../../legal/presentation/legal_screens.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../reminders/presentation/reminder_providers.dart';
import '../../settings/presentation/app_settings_controller.dart';
import '../../usage/presentation/usage_providers.dart';
import 'account_messages.dart';
import 'account_providers.dart';
import 'key_rotation_screen.dart';
import 'sign_in_screen.dart';

/// Profile: the account, the backup and the devices. Without a server in
/// this build, it says so plainly: everything stays on the phone.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountStateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProfile)),
      body: state.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (state) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.accountTitle,
                    style: context.textStyles.titleMedium,
                  ),
                  const SizedBox(height: EripooSpacing.sm),
                  _AccountCard(state),
                  if (latencyToolAvailable(ref.watch(appConfigProvider))) ...[
                    const SizedBox(height: EripooSpacing.sm),
                    EripooCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LatencyScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.speed),
                          const SizedBox(width: EripooSpacing.md),
                          Expanded(child: Text(l10n.latencyTitle)),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ],
                  if (state is Linked) ...[
                    const SizedBox(height: EripooSpacing.xl),
                    Text(l10n.syncTitle, style: context.textStyles.titleMedium),
                    const SizedBox(height: EripooSpacing.sm),
                    const _SyncCard(),
                    const SizedBox(height: EripooSpacing.sm),
                    EripooCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DevicesScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.devices),
                          const SizedBox(width: EripooSpacing.md),
                          Expanded(child: Text(l10n.devicesTitle)),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                    const SizedBox(height: EripooSpacing.xl),
                    Text(
                      l10n.securityTitle,
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: EripooSpacing.sm),
                    EripooCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const KeyRotationScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key),
                          const SizedBox(width: EripooSpacing.md),
                          Expanded(child: Text(l10n.rotationEntry)),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: EripooSpacing.sm),
                  EripooCard(
                    onTap: () => context.go(AppRoutes.trash),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline),
                        const SizedBox(width: EripooSpacing.md),
                        Expanded(child: Text(l10n.trashTitle)),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                  const SizedBox(height: EripooSpacing.xl),
                  Text(
                    l10n.settingsTitle,
                    style: context.textStyles.titleMedium,
                  ),
                  const SizedBox(height: EripooSpacing.sm),
                  const _PreferencesCard(),
                  const SizedBox(height: EripooSpacing.sm),
                  EripooCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalScreen(),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.policy_outlined),
                        const SizedBox(width: EripooSpacing.md),
                        Expanded(child: Text(l10n.legalTitle)),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferencesCard extends ConsumerWidget {
  const _PreferencesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final celebrations = ref.watch(
      appSettingsProvider.select((s) => s.celebrations),
    );
    final reminders = ref.watch(
      appSettingsProvider.select((s) => s.missionReminders),
    );
    final usageStats = ref.watch(
      appSettingsProvider.select((s) => s.usageStats),
    );
    Future<void> setReminders(bool on) async {
      final platform = ref.read(reminderPlatformProvider);
      final settings = ref.read(appSettingsProvider.notifier);
      final messenger = ScaffoldMessenger.of(context);
      if (!on) {
        settings.setMissionReminders(false);
        await platform.cancel().catchError((Object _) {});
        return;
      }
      if (!await platform.requestPermission()) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.remindersDenied)));
        return;
      }
      settings.setMissionReminders(true);
      await platform.schedule().catchError((Object _) {});
    }

    return EripooCard(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: celebrations,
            title: Text(l10n.settingsCelebrations),
            subtitle: Text(l10n.settingsCelebrationsHelp),
            onChanged: ref.read(appSettingsProvider.notifier).setCelebrations,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: usageStats,
            title: Text(l10n.settingsUsageStats),
            subtitle: Text(l10n.settingsUsageStatsHelp),
            onChanged: (on) {
              ref.read(appSettingsProvider.notifier).setUsageStats(on);
              if (!on) ref.read(usageCounterProvider).forgetPending();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders,
            title: Text(l10n.settingsReminders),
            subtitle: Text(l10n.settingsRemindersHelp),
            onChanged: setReminders,
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard(this.state);
  final AccountState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    void open({required bool create}) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SignInScreen(create: create)),
    );
    final signIn = EripooButton(
      label: l10n.accountSignIn,
      variant: EripooButtonVariant.secondary,
      onPressed: () => open(create: false),
    );
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (state) {
          AccountUnavailable() => [Text(l10n.accountUnavailable)],
          SignedOut() => [
            Text(l10n.accountGuestBody),
            const SizedBox(height: EripooSpacing.md),
            EripooButton(
              label: l10n.accountCreate,
              onPressed: () => open(create: true),
            ),
            const SizedBox(height: EripooSpacing.sm),
            signIn,
          ],
          NotLinked() => [
            Text(l10n.accountGuestBody),
            const SizedBox(height: EripooSpacing.md),
            signIn,
          ],
          SessionEnded() => [
            Text(l10n.syncStateSignIn),
            const SizedBox(height: EripooSpacing.md),
            signIn,
          ],
          OtherAccount() => [Text(l10n.accountMismatch)],
          Linked(:final user) => [
            Text(l10n.accountSignedInAs(user.email ?? '')),
            const SizedBox(height: EripooSpacing.md),
            EripooButton(
              label: l10n.accountSignOut,
              icon: Icons.logout,
              variant: EripooButtonVariant.secondary,
              onPressed: () => _signOut(context, ref),
            ),
            const SizedBox(height: EripooSpacing.sm),
            EripooButton(
              label: l10n.accountDelete,
              icon: Icons.delete_forever_outlined,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => _deleteAccount(context, ref),
            ),
          ],
        },
      ),
    );
  }
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final lifecycle = ref.read(accountLifecycleProvider);
  if (lifecycle == null) return;
  final pending = await ref.read(pendingChangesProvider.future);
  if (!context.mounted) return;
  final ok = await showEripooConfirmDialog(
    context,
    title: l10n.accountSignOutTitle,
    message: pending == 0
        ? l10n.accountSignOutBody
        : '${l10n.accountSignOutBody}\n\n${l10n.accountSignOutUnsaved(pending)}',
    confirmLabel: l10n.accountErase,
    destructive: true,
  );
  if (!ok) return;
  await lifecycle.signOutAndErase(
    deviceId: ref.read(appServicesProvider).keys.deviceId,
  );
  await ref.read(appRestartProvider)();
}

/// Before deleting the account: offers to export the file as a PDF first
/// (only when the project has a chapter to export). False when cancelled.
Future<bool> _offerExport(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final synthesis = await ref.read(synthesisProvider.future);
  if (synthesis == null || !context.mounted) return true;
  final parts = documentBuilder(context, ref, synthesis).dossier();
  final ready = parts.where((p) => p.filled).toList();
  if (ready.isEmpty) return true;
  final export = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.accountDeleteExportTitle),
      content: Text(l10n.accountDeleteExportBody),
      actions: [
        EripooButton(
          label: l10n.accountDeleteSkipExport,
          variant: EripooButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EripooButton(
          label: l10n.accountDeleteExport,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (export == null) return false;
  if (export && context.mounted) {
    await exportPdf(
      context,
      ref,
      kind: PdfKind.dossier,
      title: synthesis.project.title,
      parts: ready,
      missing: parts.where((p) => !p.filled).toList(),
    );
  }
  return true;
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final lifecycle = ref.read(accountLifecycleProvider);
  final backend = ref.read(accountBackendProvider).value;
  final email = ref.read(authUserProvider).value?.email;
  if (lifecycle == null || backend == null) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!await _offerExport(context, ref) || !context.mounted) return;
  final ok = await showEripooConfirmDialog(
    context,
    title: l10n.accountDeleteTitle,
    message: l10n.accountDeleteBody,
    confirmLabel: l10n.accountDeleteConfirm,
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  if (!await confirmOwner(context, ref, reason: l10n.ownerReason)) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.ownerFailed)));
    return;
  }
  if (!context.mounted) return;
  // A sign-in of less than 10 minutes, before anything is deleted.
  if (email != null) {
    final password = await askPassword(context);
    if (password == null) return;
    try {
      await backend.auth.signInWithEmail(email, password);
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(authMessage(l10n, e))));
      return;
    }
  }
  messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleteWorking)));
  try {
    await lifecycle.deleteAccount();
  } on SyncRemoteFailure {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.accountDeleteFailed)));
    return;
  }
  await ref.read(appRestartProvider)();
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(syncControllerProvider);
    final state = ref.watch(syncStateProvider).value ?? SyncState.idle;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final db = ref.watch(appDatabaseProvider);
    final text = switch (state) {
      SyncState.idle => l10n.syncStateIdle,
      SyncState.running => l10n.syncStateRunning,
      SyncState.saved when pending == 0 => l10n.syncStateSaved,
      SyncState.saved || SyncState.waiting => l10n.syncStateWaiting(pending),
      SyncState.signInNeeded => l10n.syncStateSignIn,
      SyncState.removed => l10n.syncStateRemoved,
      SyncState.keyOutdated => l10n.syncStateKeyOutdated,
      SyncState.restartNeeded => l10n.syncStateRestart,
    };
    final rekeying = ref.watch(rotationInProgressProvider).value ?? false;
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(switch (state) {
                SyncState.saved when pending == 0 => Icons.cloud_done_outlined,
                SyncState.running => Icons.cloud_sync_outlined,
                _ => Icons.cloud_off_outlined,
              }),
              const SizedBox(width: EripooSpacing.md),
              Expanded(child: Text(text)),
            ],
          ),
          if (rekeying) ...[
            const SizedBox(height: EripooSpacing.sm),
            Text(l10n.rotationRunning, style: context.textStyles.bodySmall),
          ],
          const SizedBox(height: EripooSpacing.sm),
          if (state == SyncState.removed || state == SyncState.restartNeeded)
            EripooButton(
              label: l10n.actionRestart,
              onPressed: () => ref.read(appRestartProvider)(),
            )
          else if (state == SyncState.keyOutdated)
            EripooButton(
              label: l10n.syncUseNewCode,
              icon: Icons.password,
              onPressed: () => openWithNewKey(context, ref),
            )
          else ...[
            EripooButton(
              label: l10n.syncNow,
              icon: Icons.sync,
              variant: EripooButtonVariant.secondary,
              onPressed: state == SyncState.running
                  ? null
                  : controller?.scheduler.syncNow,
            ),
            FutureBuilder<String?>(
              future: db.readValue(SyncCycle.mediaOnMobileDataKey),
              builder: (context, snapshot) {
                var on = snapshot.data == '1';
                return StatefulBuilder(
                  builder: (context, setState) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: on,
                    title: Text(l10n.syncPhotosMobile),
                    subtitle: Text(l10n.syncPhotosMobileHelp),
                    onChanged: (value) async {
                      await db.writeValue(
                        SyncCycle.mediaOnMobileDataKey,
                        value ? '1' : '0',
                      );
                      setState(() => on = value);
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
