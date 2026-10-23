// Moves content between content/*.yaml and the back-office documents
// (schema authoring, NEXT_STEPS C-14 lot 3). Used by the "Content sync"
// workflow; nothing here talks to the network.
//
//   dart run tool/content_sync.dart import-sql > import.sql
//     SQL inserting every content file as a document, without
//     overwriting a document already edited in the back-office.
//   dart run tool/content_sync.dart export documents.json
//     Writes content/<path> from [{"path": ..., "body": ...}].
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const sourceDir = 'content';
final _pathPattern = RegExp(r'^[a-z0-9_/]+\.yaml$');

Object? plain(Object? yaml) => switch (yaml) {
  YamlMap() => {for (final e in yaml.entries) e.key.toString(): plain(e.value)},
  YamlList() => [for (final v in yaml) plain(v)],
  _ => yaml,
};

/// Content files relative to [root], sorted.
List<String> contentPaths(String root) =>
    [
        for (final f in Directory(root).listSync(recursive: true))
          if (f is File && f.path.endsWith('.yaml'))
            f.path.substring(root.length + 1).replaceAll(r'\', '/'),
      ]
      ..removeWhere((p) => !_pathPattern.hasMatch(p))
      ..sort();

String importSql(String root) {
  final out = StringBuffer('begin;\n');
  for (final path in contentPaths(root)) {
    final body = jsonEncode(
      plain(loadYaml(File('$root/$path').readAsStringSync())),
    );
    if (body.contains(r'$eripoo$')) throw StateError('delimiter in $path');
    out.writeln(
      'insert into authoring.documents (path, body) values '
      "('$path', \$eripoo\$$body\$eripoo\$::jsonb) "
      'on conflict (path) do nothing;',
    );
  }
  out.writeln('commit;');
  return out.toString();
}

/// YAML for [value]: block style, every string double-quoted with JSON
/// escapes (valid YAML), so no value changes type on the way back.
String toYaml(Object? value) => '${_lines(value).join('\n')}\n';

bool _nested(Object? v) =>
    (v is Map && v.isNotEmpty) || (v is List && v.isNotEmpty);

final _plainKey = RegExp(r'^[a-z_][a-z0-9_.]*$');

List<String> _lines(Object? v) {
  if (v is Map<String, Object?>) {
    return [
      for (final e in v.entries) ...[
        if (_nested(e.value)) ...[
          '${_key(e.key)}:',
          for (final line in _lines(e.value)) '  $line',
        ] else
          '${_key(e.key)}: ${jsonEncode(e.value)}',
      ],
    ];
  }
  if (v is List<Object?>) {
    return [
      for (final item in v)
        if (_nested(item))
          for (final (i, line) in _lines(item).indexed)
            i == 0 ? '- $line' : '  $line'
        else
          '- ${jsonEncode(item)}',
    ];
  }
  return [jsonEncode(v)];
}

String _key(String key) => _plainKey.hasMatch(key) ? key : jsonEncode(key);

/// [value] with its map keys in [model]'s order where [model] has them
/// (list items matched by position), then the others in their own order.
Object? orderLike(Object? value, Object? model) {
  if (value is Map<String, Object?>) {
    final m = model is Map<String, Object?> ? model : const <String, Object?>{};
    final keys = [
      for (final k in m.keys)
        if (value.containsKey(k)) k,
      for (final k in value.keys)
        if (!m.containsKey(k)) k,
    ];
    return {for (final k in keys) k: orderLike(value[k], m[k])};
  }
  if (value is List<Object?>) {
    final m = model is List<Object?> ? model : const <Object?>[];
    return [
      for (var i = 0; i < value.length; i++)
        orderLike(value[i], i < m.length ? m[i] : null),
    ];
  }
  return value;
}

void export(String root, List<Object?> documents) {
  for (final d in documents.cast<Map<String, Object?>>()) {
    final path = d['path']! as String;
    if (!_pathPattern.hasMatch(path) || path.contains('..')) {
      throw FormatException('invalid path', path);
    }
    final file = File('$root/$path')..parent.createSync(recursive: true);
    // The database does not keep key order: follow the current file's.
    final previous = file.existsSync()
        ? plain(loadYaml(file.readAsStringSync()))
        : null;
    file.writeAsStringSync(
      '# Exported from the back-office (tool/content_sync.dart).\n'
      '${toYaml(orderLike(d['body'], previous))}',
    );
  }
}

void main(List<String> args) {
  switch (args) {
    case ['import-sql']:
      stdout.write(importSql(sourceDir));
    case ['export', final file]:
      final docs = jsonDecode(File(file).readAsStringSync()) as List<Object?>;
      export(sourceDir, docs);
      print('${docs.length} documents written to $sourceDir/');
    default:
      stderr.writeln('usage: content_sync.dart import-sql | export <file>');
      exitCode = 64;
  }
}
