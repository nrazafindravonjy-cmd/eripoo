import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release hardening of the Android app (docs/RELEASE_CHECKLIST.md),
/// checked on the sources. The merged manifest of a built APK is checked
/// in CI by tool/check_apk.sh.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  Set<String> permissions(String xml, {required bool removed}) => {
    for (final m in RegExp(
      r'<uses-permission\s+android:name="android\.permission\.(\w+)"([^>]*)/>',
    ).allMatches(xml))
      if (m.group(2)!.contains('tools:node="remove"') == removed) m.group(1)!,
  };

  test('only the permissions Eripoo needs are declared', () {
    // Each one is explained next to its declaration in the manifest.
    expect(permissions(manifest, removed: false), {
      'INTERNET',
      'USE_BIOMETRIC',
      'RECORD_AUDIO',
    });
    expect(permissions(manifest, removed: true), {
      'WRITE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
      'POST_NOTIFICATIONS',
    });
  });

  test('no backup, no clear text, one exported activity', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      RegExp('android:exported="true"').allMatches(manifest),
      hasLength(1),
    );
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(rules)!.group(1)!;
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
      ]) {
        expect(body, contains('<exclude domain="$domain" />'));
      }
    }
  });

  test('clear text is allowed only in debug builds (local Supabase)', () {
    for (final variant in ['profile', 'release']) {
      final file = File('android/app/src/$variant/AndroidManifest.xml');
      if (file.existsSync()) {
        expect(file.readAsStringSync(), isNot(contains('CleartextTraffic')));
      }
    }
  });

  test('release signing secrets stay outside Git', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, isNot(contains(RegExp(r'Password\s*=\s*"'))));
    final tracked = (Process.runSync('git', ['ls-files']).stdout as String)
        .split('\n')
        .where(
          (p) =>
              p.endsWith('.jks') ||
              p.endsWith('.keystore') ||
              p.endsWith('key.properties'),
        );
    expect(tracked, isEmpty);
    final ignored = Process.runSync('git', [
      'check-ignore',
      '-q',
      'android/key.properties',
    ]);
    expect(ignored.exitCode, 0);
  });
}
