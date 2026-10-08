import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/startup/local_data_eraser.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Why this phone's data was erased last time, until the user has read it.
final erasureReasonProvider = FutureProvider<ErasureReason?>(
  (ref) => LocalDataEraser.lastReason(ref.watch(secureKeyStoreProvider)),
);

/// After an erasure, the app starts empty: this says why, once, simply.
class ErasureNotice extends ConsumerWidget {
  const ErasureNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reason = ref.watch(erasureReasonProvider).value;
    if (reason == null) return const SizedBox.shrink();
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
                  const Icon(Icons.info_outline),
                  const SizedBox(width: EripooSpacing.md),
                  Expanded(
                    child: Text(switch (reason) {
                      ErasureReason.userReset => l10n.erasedReset,
                      ErasureReason.deviceRevoked => l10n.erasedRevoked,
                      ErasureReason.signedOut => l10n.erasedSignedOut,
                      ErasureReason.accountDeleted => l10n.erasedAccountDeleted,
                    }),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: EripooButton(
                  label: l10n.actionClose,
                  variant: EripooButtonVariant.tertiary,
                  onPressed: () async {
                    await LocalDataEraser.acknowledge(
                      ref.read(secureKeyStoreProvider),
                    );
                    ref.invalidate(erasureReasonProvider);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
