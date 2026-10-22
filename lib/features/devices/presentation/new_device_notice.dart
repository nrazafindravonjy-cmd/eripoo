import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../account/presentation/account_providers.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/new_device_alerts.dart';
import 'devices_screen.dart';

final newDeviceAlertsProvider = Provider<NewDeviceAlerts>(
  (ref) => NewDeviceAlerts(ref.watch(appDatabaseProvider)),
);

/// The account's devices and those added since this phone last looked.
/// Offline or without an account: nothing to tell.
final newDevicesProvider =
    FutureProvider.autoDispose<
      ({List<RemoteDevice> all, List<RemoteDevice> added})
    >((ref) async {
      const none = (all: <RemoteDevice>[], added: <RemoteDevice>[]);
      final backend = await ref.watch(accountBackendProvider.future);
      if (backend == null) return none;
      final List<RemoteDevice> all;
      try {
        all = await backend.sync.listDevices(
          currentDeviceId: ref.watch(appServicesProvider).keys.deviceId,
        );
      } on Object {
        return none;
      }
      final added = await ref.read(newDeviceAlertsProvider).pending(all);
      return (all: all, added: added);
    });

/// On Home: "a new device was added" (docs/SECURITY.md §6.8), with the
/// way to remove it. Names and dates only, never project content.
class NewDeviceNotice extends ConsumerWidget {
  const NewDeviceNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(newDevicesProvider).value;
    if (state == null || state.added.isEmpty) return const SizedBox.shrink();
    Future<void> acknowledge() async {
      await ref.read(newDeviceAlertsProvider).acknowledge(state.all);
      ref.invalidate(newDevicesProvider);
    }

    return ReadableColumn(
      child: Padding(
        padding: const EdgeInsets.only(bottom: EripooSpacing.lg),
        child: EripooCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.phonelink_lock_outlined),
                  const SizedBox(width: EripooSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.newDeviceTitle,
                          style: context.textStyles.titleMedium,
                        ),
                        const SizedBox(height: EripooSpacing.xs),
                        for (final d in state.added)
                          Text(
                            l10n.newDeviceItem(
                              d.label,
                              context.formatter.date(d.createdAt.toLocal()),
                            ),
                          ),
                        const SizedBox(height: EripooSpacing.sm),
                        Text(l10n.newDeviceBody),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EripooSpacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: EripooSpacing.sm,
                children: [
                  EripooButton(
                    label: l10n.newDeviceItsMe,
                    variant: EripooButtonVariant.tertiary,
                    onPressed: acknowledge,
                  ),
                  EripooButton(
                    label: l10n.newDeviceReview,
                    onPressed: () async {
                      await acknowledge();
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DevicesScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
