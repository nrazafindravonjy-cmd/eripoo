// Latency measurement for the production region choice (DEVELOPMENT_PLAN
// P5): median and 95th percentile, a plain-text report, and the screen
// only in development builds, never in production.
import 'package:eripoo/core/config/app_config.dart';
import 'package:eripoo/features/latency/domain/latency_stats.dart';
import 'package:eripoo/features/latency/presentation/latency_screen.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig config(AppEnvironment env) => AppConfig(
  environment: env,
  supabaseUrl: 'https://example.supabase.co',
  supabaseAnonKey: 'public-anon-key',
);

void main() {
  test('median and 95th percentile (nearest rank)', () {
    final samples = [for (var i = 1; i <= 100; i++) i * 10];
    final stats = LatencyStats.of(samples.reversed.toList(), failures: 3)!;
    expect(stats.median, 500);
    expect(stats.p95, 950);
    expect(stats.min, 10);
    expect(stats.max, 1000);
    expect(stats.failures, 3);
    expect(stats.sufficient, isTrue);
    expect(LatencyStats.of([]), isNull);
    expect(LatencyStats.of([120])!.p95, 120);
  });

  test('the report keeps every measure, in order, and the note on a line', () {
    final report = LatencyStats.of([300, 100, 200])!.report(
      url: 'https://example.supabase.co',
      network: 'mobile',
      note: 'Antananarivo,\n4G',
      takenAt: DateTime.utc(2026, 10, 22, 9),
    );
    expect(report, contains('median_ms=200'));
    expect(report, contains('raw_ms=300,100,200'));
    expect(report, contains('note=Antananarivo, 4G'));
    expect(report, contains('date=2026-10-22T09:00:00.000Z'));
    expect(report.split('\n').first, 'eripoo-latency v1');
  });

  test('only in development builds, never in production', () {
    expect(latencyToolAvailable(config(AppEnvironment.development)), isTrue);
    expect(latencyToolAvailable(config(AppEnvironment.production)), isFalse);
    expect(latencyToolAvailable(config(AppEnvironment.local)), isFalse);
  });
}
