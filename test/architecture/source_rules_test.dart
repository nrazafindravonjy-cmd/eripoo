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

  test('no analytics, crash-reporting or AI SDK in the dependencies', () {
    // Private data must never leave through a third-party SDK
    // (docs/SECURITY.md). Analytics are a later, opt-in, self-hosted
    // decision (D7, D8); no project data is sent to an AI model.
    final lock = File('pubspec.lock').readAsStringSync();
    final forbidden = RegExp(
      r'^  (firebase_\w+|sentry\w*|\w*crashlytics\w*|amplitude\w*|mixpanel\w*|'
      r'segment\w*|posthog\w*|datadog\w*|bugsnag\w*|appcenter\w*|'
      r'google_generative_ai|openai\w*|dart_openai|langchain\w*|'
      r'anthropic\w*|firebase_vertexai|google_mlkit\w*):',
      multiLine: true,
    );
    expect(forbidden.allMatches(lock).map((m) => m.group(1)).toList(), isEmpty);
  });

  test('exceptions carry no text (no user input in error messages)', () {
    final classHeader = RegExp(
      r'^(?:sealed |final |abstract )*class (\w+)[^{]*(?:implements Exception|extends \w*(?:Failure|Exception))[^{]*\{',
      multiLine: true,
    );
    final offenders = <String>[];
    for (final f in dartFiles('lib')) {
      final source = f.readAsStringSync();
      for (final match in classHeader.allMatches(source)) {
        final rest = source.substring(match.end);
        final end = rest.indexOf(RegExp(r'^}', multiLine: true));
        final body = end < 0 ? rest : rest.substring(0, end);
        if (RegExp(r'final (String|Object|dynamic)\??\s').hasMatch(body) ||
            body.contains('String get message')) {
          offenders.add('${rel(f)}: ${match.group(1)}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('test data is fictitious (no real e-mail address or phone number)', () {
    final dirs = ['test', 'integration_test', 'supabase/tests'];
    final email = RegExp(r'[\w.+-]+@([\w-]+\.)+[a-z]{2,}');
    final allowedDomains = RegExp(r'@(?:[\w-]+\.)*example\.(com|invalid|org)$');
    // Malagasy mobile numbers: +261 3x … or 03x xx xxx xx.
    final phone = RegExp(
      r'(\+261[\s.]?3\d|\b03[234789])[\s.]?\d{2}[\s.]?\d{3}[\s.]?\d{2}\b',
    );
    final offenders = <String>[];
    for (final dir in dirs) {
      for (final f in Directory(
        dir,
      ).listSync(recursive: true).whereType<File>()) {
        if (!(f.path.endsWith('.dart') || f.path.endsWith('.sql'))) continue;
        final content = f.readAsStringSync();
        for (final m in email.allMatches(content)) {
          if (!allowedDomains.hasMatch(m.group(0)!)) {
            offenders.add('${f.path}: ${m.group(0)}');
          }
        }
        if (phone.hasMatch(content)) offenders.add('${f.path}: phone number');
      }
    }
    expect(offenders, isEmpty);
  });

  test('secure storage never uses the biometric key cipher', () {
    // Crashes on Android 7-8 and prompts for authentication at start on
    // locked phones (docs/SECURITY.md §4.4); found on the CI emulator.
    final source = File('lib/security/secure_key_store.dart')
        .readAsStringSync();
    expect(
      source,
      contains('KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding'),
    );
    expect(source, isNot(contains('KeyCipherAlgorithm.AES_GCM_NoPadding')));
    expect(source, isNot(contains('AndroidOptions.biometric')));
  });
}
