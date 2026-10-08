// Checks that the official documents behind content/formalization.yaml
// have not changed since they were read: downloads each source that has a
// sha256 and compares. Needs network access to the official sites.
//
//   dart run tool/check_sources.dart
//
// A changed document is not an error in the app: it means the content
// must be read again, updated, re-dated and re-reviewed (docs/DEVELOPMENT_PLAN.md,
// Phase 8). Exit code 1 when a source changed or could not be read.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eripoo/content/formalization.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:yaml/yaml.dart';

Object? _plain(Object? node) => switch (node) {
  YamlMap() => {for (final e in node.entries) '${e.key}': _plain(e.value)},
  YamlList() => [for (final v in node) _plain(v)],
  _ => node,
};

Future<void> main() async {
  final yaml = loadYaml(File('content/formalization.yaml').readAsStringSync());
  final content = FormalizationContent.read(JsonReader(_plain(yaml)));
  final client = HttpClient();
  var failed = false;
  for (final s in content.sources) {
    if (s.sha256 == null) {
      stdout.writeln('SKIP  ${s.id} (page, no fingerprint)');
      continue;
    }
    try {
      final request = await client.getUrl(Uri.parse(s.url));
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      final hash = sha256.convert(bytes).toString();
      if (response.statusCode == 200 && hash == s.sha256) {
        stdout.writeln('SAME  ${s.id}');
      } else {
        failed = true;
        stdout.writeln(
          'CHANGED ${s.id}: HTTP ${response.statusCode}, sha256 $hash',
        );
      }
    } on Exception catch (e) {
      failed = true;
      stdout.writeln('ERROR ${s.id}: ${e.runtimeType}');
    }
  }
  client.close();
  exit(failed ? 1 : 0);
}
