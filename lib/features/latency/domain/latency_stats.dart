/// Latency to the Supabase project, to choose the production region
/// (docs/DEVELOPMENT_PLAN.md P5): at least 100 measures per place and
/// network, median and 95th percentile. Development builds only.
class LatencyStats {
  const LatencyStats({
    required this.samples,
    required this.failures,
    required this.median,
    required this.p95,
    required this.min,
    required this.max,
  });

  /// Successful measures, in milliseconds, in the order taken.
  final List<int> samples;

  /// Requests that failed or timed out.
  final int failures;
  final int median;
  final int p95;
  final int min;
  final int max;

  static const minimumSamples = 100;

  /// Null without any successful measure.
  static LatencyStats? of(List<int> samples, {int failures = 0}) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    return LatencyStats(
      samples: List.unmodifiable(samples),
      failures: failures,
      median: percentile(sorted, 50),
      p95: percentile(sorted, 95),
      min: sorted.first,
      max: sorted.last,
    );
  }

  /// Nearest-rank percentile of an ascending, non-empty list.
  static int percentile(List<int> sorted, int p) {
    final rank = (p / 100 * sorted.length).ceil();
    return sorted[(rank - 1).clamp(0, sorted.length - 1)];
  }

  /// Enough measures for the report.
  bool get sufficient => samples.length >= minimumSamples;

  /// Plain text for the measurement report (no personal data: the
  /// project's public URL, the network kind and the user's own note).
  String report({
    required String url,
    required String network,
    required String note,
    required DateTime takenAt,
  }) => [
    'eripoo-latency v1',
    'date=${takenAt.toUtc().toIso8601String()}',
    'url=$url',
    'network=$network',
    'note=${note.replaceAll('\n', ' ').trim()}',
    'samples=${samples.length}',
    'failures=$failures',
    'median_ms=$median',
    'p95_ms=$p95',
    'min_ms=$min',
    'max_ms=$max',
    'raw_ms=${samples.join(',')}',
  ].join('\n');
}
