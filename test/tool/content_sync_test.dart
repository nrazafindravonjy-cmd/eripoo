import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/content_sync.dart';

void main() {
  test('every content file survives an export unchanged', () {
    final paths = contentPaths(sourceDir);
    expect(paths, contains('quests/q05_competition.yaml'));
    for (final path in paths) {
      final original = plain(
        loadYaml(File('$sourceDir/$path').readAsStringSync()),
      );
      final again = plain(loadYaml(toYaml(original)));
      expect(jsonEncode(again), jsonEncode(original), reason: path);
    }
  });

  test('strings never change type', () {
    final value = {
      'a': 'yes',
      'b': '012',
      'c': 'null',
      'd': 'line\nbreak: "x"',
      'e': <Object?>[],
      'f': <String, Object?>{},
      'g': [
        [1, 2],
        {'h': true},
      ],
    };
    expect(jsonEncode(plain(loadYaml(toYaml(value)))), jsonEncode(value));
  });

  test('export keeps the key order of the current file', () {
    expect(
      jsonEncode(
        orderLike(
          {
            'b': 1,
            'new': 2,
            'a': [
              {'y': 1, 'x': 2},
            ],
          },
          {
            'a': [
              {'x': 0, 'y': 0},
            ],
            'b': 0,
          },
        ),
      ),
      '{"a":[{"x":2,"y":1}],"b":1,"new":2}',
    );
  });

  test('the import keeps documents already edited', () {
    final sql = importSql(sourceDir);
    expect(
      'on conflict (path) do nothing'.allMatches(sql).length,
      contentPaths(sourceDir).length,
    );
  });

  test('export refuses paths outside the content tree', () {
    final dir = Directory.systemTemp.createTempSync('content_sync');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(
      () => export(dir.path, [
        {'path': '../x.yaml', 'body': <String, Object?>{}},
      ]),
      throwsFormatException,
    );
    export(dir.path, [
      {
        'path': 'quests/q99.yaml',
        'body': {'id': 'q99'},
      },
    ]);
    expect(
      plain(loadYaml(File('${dir.path}/quests/q99.yaml').readAsStringSync())),
      {'id': 'q99'},
    );
  });
}
