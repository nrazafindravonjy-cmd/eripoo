import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// `{name}` or `{name, select, …}`; not the branches of a select
/// (`case{Text}`), which follow their case word and are translated.
Set<String> _placeholders(String message) =>
    RegExp(r'(?<!\w)\{(\w+)[},]')
        .allMatches(message)
        .map((m) => m.group(1)!)
        .toSet();

void main() {
  final fr = _readJson('lib/l10n/app_fr.arb');
  final mg = _readJson('lib/l10n/app_mg.arb');
  final en = _readJson('lib/l10n/app_en.arb');

  test('every key exists in mg, fr and en', () {
    expect(_messageKeys(mg), _messageKeys(fr));
    expect(_messageKeys(en), _messageKeys(fr));
  });

  test('no translation is empty', () {
    for (final arb in [fr, mg, en]) {
      for (final key in _messageKeys(arb)) {
        expect((arb[key] as String).trim(), isNotEmpty, reason: key);
      }
    }
  });

  test('placeholders match across languages', () {
    for (final key in _messageKeys(fr)) {
      final expected = _placeholders(fr[key] as String);
      expect(_placeholders(mg[key] as String), expected, reason: 'mg $key');
      expect(_placeholders(en[key] as String), expected, reason: 'en $key');
    }
  });

  test('every template key is documented for translators', () {
    for (final key in _messageKeys(fr)) {
      final meta = fr['@$key'] as Map<String, dynamic>?;
      expect(meta?['description'], isA<String>(), reason: key);
    }
  });

  test('every Malagasy string has a review status (D13)', () {
    final status =
        _readJson('lib/l10n/mg_review_status.json')['strings']
            as Map<String, dynamic>;
    expect(status.keys.toSet(), _messageKeys(mg));
    expect(
      status.values.toSet().difference({'needs_review', 'reviewed'}),
      isEmpty,
    );
  });
}
