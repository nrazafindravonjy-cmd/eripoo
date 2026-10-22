// Legal texts (NEXT_STEPS C-12): placeholders are never offered for
// acceptance; validated texts are, again at each new version; validated
// texts must include the privacy policy and the terms.
import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/legal/application/legal_acceptance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

LegalContent legal({
  String version = '1',
  String status = 'validated',
  List<String> ids = const ['privacy', 'terms'],
}) => LegalContent.read(
  JsonReader({
    'version': version,
    'status': status,
    'documents': [
      for (final id in ids)
        {
          'id': id,
          'title': {'fr': 'Titre', 'mg': 'Lohateny', 'en': 'Title'},
          'body': [
            {'fr': 'Texte.', 'mg': 'Lahatsoratra.', 'en': 'Text.'},
          ],
        },
    ],
  }),
);

void main() {
  late AppDatabase db;
  late LegalAcceptance acceptance;
  setUp(() {
    db = memoryDatabase();
    acceptance = LegalAcceptance(db);
  });
  tearDown(() => db.close());

  test('the shipped texts are placeholders: nothing is asked', () async {
    final shipped = basePack().legal!;
    expect(shipped.validated, isFalse);
    expect(await acceptance.needed(shipped), isFalse);
    expect(await acceptance.needed(null), isFalse);
  });

  test('validated texts are asked once, then again at a new version', () async {
    final v1 = legal();
    expect(await acceptance.needed(v1), isTrue);
    await acceptance.accept(v1);
    expect(await acceptance.needed(v1), isFalse);
    expect(await acceptance.needed(legal(version: '2')), isTrue);
  });

  test('validated texts need both the privacy policy and the terms', () {
    final base = basePack();
    ContentPack withLegal(LegalContent l) => ContentPack(
      packId: base.packId,
      version: base.version,
      minAppVersion: base.minAppVersion,
      blockTypes: base.blockTypes,
      quests: base.quests,
      missions: base.missions,
      sections: base.sections,
      tools: base.tools,
      badges: base.badges,
      legal: l,
    );
    expect(validatePack(withLegal(legal())).errors, isEmpty);
    expect(
      validatePack(withLegal(legal(ids: ['privacy']))).errors,
      contains('legal: validated texts need the privacy policy and the terms'),
    );
    expect(
      validatePack(withLegal(legal(status: 'pending', ids: ['privacy'])))
          .errors,
      isEmpty,
    );
  });
}
