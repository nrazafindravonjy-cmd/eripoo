import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/sync/sync_setup.dart';
import '../../../core/config/app_config.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/sync_cycle.dart';
import '../../account/presentation/account_providers.dart';
import '../data/latency_probe.dart';
import '../domain/latency_stats.dart';

/// Only in development builds: never offered in production.
bool latencyToolAvailable(AppConfig config) =>
    config.environment == AppEnvironment.development && config.hasBackend;

/// Measures the round trip to the development project, for the latency
/// report from Madagascar (docs/DEVELOPMENT_PLAN.md P5).
class LatencyScreen extends ConsumerStatefulWidget {
  const LatencyScreen({super.key});

  @override
  ConsumerState<LatencyScreen> createState() => _LatencyScreenState();
}

class _LatencyScreenState extends ConsumerState<LatencyScreen> {
  final _note = TextEditingController();
  bool _running = false;
  int _done = 0;
  String _network = 'unknown';
  LatencyStats? _stats;
  int _failures = 0;
  DateTime? _takenAt;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final config = ref.read(appConfigProvider);
    final probe = LatencyProbe(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
    final network = switch (await currentNetwork()) {
      NetworkKind.unmetered => 'wifi',
      NetworkKind.metered => 'mobile',
      NetworkKind.none => 'none',
    };
    setState(() {
      _running = true;
      _done = 0;
      _stats = null;
      _network = network;
      _takenAt = DateTime.now();
    });
    final samples = <int>[];
    var failures = 0;
    try {
      for (var i = 0; i < LatencyStats.minimumSamples && mounted; i++) {
        final ms = await probe.measure();
        if (ms == null) {
          failures++;
        } else {
          samples.add(ms);
        }
        if (mounted) setState(() => _done = i + 1);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      probe.close();
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _failures = failures;
      _stats = LatencyStats.of(samples, failures: failures);
    });
  }

  Future<void> _copy(LatencyStats stats) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: stats.report(
          url: ref.read(appConfigProvider).supabaseUrl,
          network: _network,
          note: _note.text,
          takenAt: _takenAt ?? DateTime.now(),
        ),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.latencyCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = latencyToolAvailable(ref.watch(appConfigProvider));
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.latencyTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: !available
                ? Text(l10n.latencyNoServer)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.latencyIntro),
                      const SizedBox(height: EripooSpacing.md),
                      TextField(
                        controller: _note,
                        enabled: !_running,
                        decoration: InputDecoration(
                          labelText: l10n.latencyNoteLabel,
                        ),
                      ),
                      const SizedBox(height: EripooSpacing.md),
                      EripooButton(
                        label: l10n.latencyStart,
                        expand: true,
                        onPressed: _running ? null : _run,
                      ),
                      const SizedBox(height: EripooSpacing.md),
                      if (_running || _done > 0)
                        Text(
                          l10n.latencyProgress(
                            _done,
                            LatencyStats.minimumSamples,
                          ),
                        ),
                      if (!_running && _done > 0) ...[
                        Text(l10n.latencyNetwork(_network)),
                        Text(l10n.latencyFailures(_failures)),
                      ],
                      if (stats != null && !_running) ...[
                        const SizedBox(height: EripooSpacing.sm),
                        Text(
                          l10n.latencyResult(
                            stats.median,
                            stats.p95,
                            stats.min,
                            stats.max,
                          ),
                          style: context.textStyles.titleSmall,
                        ),
                        const SizedBox(height: EripooSpacing.md),
                        EripooButton(
                          label: l10n.latencyCopy,
                          variant: EripooButtonVariant.secondary,
                          expand: true,
                          onPressed: () => _copy(stats),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
