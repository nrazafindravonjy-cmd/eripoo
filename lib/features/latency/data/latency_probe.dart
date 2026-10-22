import 'dart:async';
import 'dart:io';

/// One round trip to the project's Auth health endpoint (public, no
/// account needed; the anon key is public by design). Null on failure.
class LatencyProbe {
  LatencyProbe({required this.url, required this.anonKey, HttpClient? client})
    : _client = client ?? HttpClient();

  final String url;
  final String anonKey;
  final HttpClient _client;

  static const timeout = Duration(seconds: 10);

  Uri get _health => Uri.parse(url).resolve('/auth/v1/health');

  Future<int?> measure() async {
    final watch = Stopwatch()..start();
    try {
      final request = await _client.getUrl(_health).timeout(timeout);
      request.headers.set('apikey', anonKey);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      watch.stop();
      return response.statusCode < 500 ? watch.elapsedMilliseconds : null;
    } on Object {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
