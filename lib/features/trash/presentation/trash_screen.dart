import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/trash_service.dart';

final trashServiceProvider = Provider<TrashService>(
  (ref) => TrashService(
    ref.watch(appDatabaseProvider),
    media: ref.watch(mediaStoreProvider),
  ),
);

final _trashTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(trashServiceProvider).watchChanges().map((_) => ++tick);
});

/// The trash, re-read on every change of the deletable tables.
final trashItemsProvider = FutureProvider<List<TrashItem>>((ref) {
  ref.watch(_trashTick);
  return ref.watch(trashServiceProvider).items();
});

/// Moves an element to the trash, with "Undo" on the confirmation.
Future<void> deleteWithUndo(
  BuildContext context,
  WidgetRef ref,
  TrashKind kind,
  String id,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final trash = ref.read(trashServiceProvider);
  await trash.moveToTrash(kind, id);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.movedToTrash),
        action: SnackBarAction(
          label: l10n.actionUndo,
          onPressed: () => trash.restore(kind, id),
        ),
      ),
    );
}

/// Deleted elements, restorable for 30 days (docs/OFFLINE_SYNC.md §7).
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  /// Selected elements, as "kind:id".
  final _selected = <String>{};

  static String _key(TrashItem item) => '${item.kind.name}:${item.id}';

  Future<void> _restoreSelected(List<TrashItem> items) async {
    final trash = ref.read(trashServiceProvider);
    for (final item in items) {
      if (_selected.contains(_key(item))) {
        await trash.restore(item.kind, item.id);
      }
    }
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(trashItemsProvider);
    final list = items.value ?? const <TrashItem>[];
    // Forget what disappeared (restored or purged elsewhere).
    _selected.retainWhere((k) => list.any((i) => _key(i) == k));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trashTitle)),
      bottomNavigationBar: SafeArea(
        child: EripooSelectionBar(
          visible: _selected.isNotEmpty,
          countLabel: l10n.selectionCount(_selected.length),
          actionLabel: l10n.trashRestoreSelected,
          onAction: () => _restoreSelected(list),
          clearLabel: l10n.selectionClear,
          onClear: () => setState(_selected.clear),
        ),
      ),
      body: items.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (items) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.trashExplain),
                  const SizedBox(height: EripooSpacing.lg),
                  if (items.isEmpty)
                    Text(l10n.trashEmpty, style: context.textStyles.titleMedium)
                  else ...[
                    for (final item in items) ...[
                      _TrashCard(
                        item,
                        selected: _selected.contains(_key(item)),
                        onSelect: (v) => setState(
                          () => v
                              ? _selected.add(_key(item))
                              : _selected.remove(_key(item)),
                        ),
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                    ],
                    const SizedBox(height: EripooSpacing.md),
                    EripooButton(
                      label: l10n.trashEmptyAll,
                      icon: Icons.delete_forever_outlined,
                      variant: EripooButtonVariant.danger,
                      onPressed: () => _emptyAll(context, items),
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

  Future<void> _emptyAll(BuildContext context, List<TrashItem> items) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.trashEmptyAll,
      message: l10n.trashEmptyAllConfirmBody,
      confirmLabel: l10n.trashEmptyAll,
      destructive: true,
    );
    if (!ok) return;
    final trash = ref.read(trashServiceProvider);
    for (final item in items) {
      await trash.purge(item.kind, item.id);
    }
  }
}

class _TrashCard extends ConsumerWidget {
  const _TrashCard(this.item, {required this.selected, required this.onSelect});
  final TrashItem item;
  final bool selected;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trash = ref.read(trashServiceProvider);
    final label = item.label.isNotEmpty
        ? item.label
        : item.amountMga != null
        ? context.formatter.money(item.amountMga!)
        : null;
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.trashKind(item.kind.name),
                  style: context.textStyles.labelLarge,
                ),
              ),
              Checkbox(
                value: selected,
                semanticLabel: l10n.selectItem,
                onChanged: (v) => onSelect(v ?? false),
              ),
            ],
          ),
          if (item.mediaId != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EripooSpacing.xs),
              child: Icon(
                Icons.photo_outlined,
                color: context.colors.textSecondary,
              ),
            ),
          if (label != null)
            Text(label, maxLines: 3, overflow: TextOverflow.ellipsis),
          Text(
            l10n.trashDates(
              context.formatter.dateShort(item.deletedAt.toLocal()),
              context.formatter.dateShort(item.purgeAt.toLocal()),
            ),
            style: context.textStyles.bodySmall,
          ),
          Wrap(
            spacing: EripooSpacing.sm,
            children: [
              EripooButton(
                label: l10n.trashRestore,
                icon: Icons.restore,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => trash.restore(item.kind, item.id),
              ),
              EripooButton(
                label: l10n.trashPurge,
                icon: Icons.delete_forever_outlined,
                variant: EripooButtonVariant.tertiary,
                onPressed: () async {
                  final ok = await showEripooConfirmDialog(
                    context,
                    title: l10n.trashPurgeConfirmTitle,
                    message: l10n.trashPurgeConfirmBody,
                    confirmLabel: l10n.trashPurge,
                    destructive: true,
                  );
                  if (ok) await trash.purge(item.kind, item.id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
