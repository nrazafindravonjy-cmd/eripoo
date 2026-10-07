import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/sync_cycle.dart';
import '../../../sync/sync_scheduler.dart';
import '../../devices/presentation/devices_screen.dart';
import '../../quest/presentation/journey_providers.dart';
import 'account_providers.dart';
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
                ],
              ),
            ),
          ],
        ),
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
          ],
        },
      ),
    );
  }
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
    };
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
          const SizedBox(height: EripooSpacing.sm),
          if (state == SyncState.removed)
            EripooButton(
              label: l10n.actionRestart,
              onPressed: () => ref.read(appRestartProvider)(),
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
