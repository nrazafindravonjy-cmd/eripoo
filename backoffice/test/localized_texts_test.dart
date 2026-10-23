import 'package:eripoo_backoffice/localized_texts.dart';
import 'package:eripoo_backoffice/staff_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds every localized text with its pointer', () {
    final texts = localizedTexts({
      'id': 'q05',
      'title': {'fr': 'Titre', 'en': 'Title'},
      'steps': [
        {
          'id': 's1',
          'blocks': [
            {
              'body': {'fr': 'Texte'},
            },
          ],
        },
      ],
    });
    expect(texts.map((t) => t.pointer.join('/')), [
      'title',
      'steps/0/blocks/0/body',
    ]);
    expect(texts.first.values, {'fr': 'Titre', 'en': 'Title'});
    expect(texts.last.values, {'fr': 'Texte'});
  });

  test('ignores objects without a French text', () {
    expect(
      localizedTexts({
        'complete_when': {'count': 'competitors', 'gte': 2},
      }),
      isEmpty,
    );
  });

  test('maps server error codes', () {
    expect(staffErrorFor('version_conflict'), StaffError.conflict);
    expect(staffErrorFor('mfa_required'), StaffError.mfaRequired);
    expect(staffErrorFor('not_staff'), StaffError.notStaff);
    expect(staffErrorFor('invalid_translation'), StaffError.invalid);
    expect(staffErrorFor('anything else'), StaffError.other);
  });
}
