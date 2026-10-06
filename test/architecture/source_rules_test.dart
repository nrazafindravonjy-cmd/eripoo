import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture rules from docs/ARCHITECTURE.md, checked on the sources.
void main() {
  List<File> dartFiles(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/generated/'))
          .toList();

  String rel(File f) => f.path.replaceFirst(RegExp(r'^\./'), '');

  test('colours are only defined in design tokens and theme', () {
    final allowed = {
      'lib/design_system/tokens/eripoo_colors.dart',
      'lib/design_system/theme/eripoo_theme.dart',
    };
    final pattern = RegExp(r'\bColor\(0x|\bColors\.|\bColor\.fromARGB');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (!allowed.contains(rel(f)) && pattern.hasMatch(f.readAsStringSync()))
          rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no user-visible string literal in widgets', () {
    // Text('...') / Text("...") with a literal: text must come from ARB
    // files or content packs.
    final pattern = RegExp(r'''Text\(\s*['"]''');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (pattern.hasMatch(f.readAsStringSync())) rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('domain and core layers are pure Dart', () {
    final offenders = [
      for (final f in [
        ...dartFiles('lib/core'),
        ...dartFiles('lib/features').where((f) => f.path.contains('/domain/')),
      ])
        if (f.readAsStringSync().contains("import 'package:flutter/")) rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no print in the app (redacting logger only)', () {
    final pattern = RegExp(r'\b(print|debugPrint)\(');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (pattern.hasMatch(f.readAsStringSync())) rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no secret in versioned files', () {
    final tracked = Process.runSync('git', ['ls-files']).stdout as String;
    final patterns = {
      'JWT (Supabase keys are JWTs)': RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.eyJ'),
      'Supabase secret key': RegExp(r'sb_secret_[A-Za-z0-9]'),
      'private key': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
      'service_role key assignment': RegExp(
        r'service_role_key\s*[:=]',
        caseSensitive: false,
      ),
    };
    final offenders = <String>[];
    for (final path in tracked.split('\n')) {
      if (path.isEmpty || path.endsWith('.png') || path.endsWith('.lock')) {
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) continue;
      final String content;
      try {
        content = file.readAsStringSync();
      } on FileSystemException {
        continue; // binary file
      }
      for (final entry in patterns.entries) {
        if (entry.value.hasMatch(content)) {
          offenders.add('$path (${entry.key})');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('environment files other than the example are not versioned', () {
    final tracked =
        (Process.runSync('git', ['ls-files', 'env']).stdout as String)
            .split('\n')
            .where((p) => p.isNotEmpty);
    expect(tracked.every((p) => p == 'env/example.json'), isTrue);
  });
}
