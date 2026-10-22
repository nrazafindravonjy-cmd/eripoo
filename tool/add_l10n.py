"""Adds interface strings to the fr/en/mg ARB files and marks the Malagasy
ones `needs_review` in lib/l10n/mg_review_status.json.

Usage (from the repository root), then run `flutter gen-l10n`:
    python3 tool/add_l10n.py strings.json
strings.json: {key: {"fr": .., "en": .., "mg": .., "desc": ..,
                     "placeholders": {name: {"type": ..}}}}
"""
import collections
import json
import sys

spec = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)


def load(path):
    return json.load(open(path), object_pairs_hook=collections.OrderedDict)


def save(path, data):
    with open(path, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


for lang in ['fr', 'en', 'mg']:
    path = f'lib/l10n/app_{lang}.arb'
    arb = load(path)
    for key, value in spec.items():
        if key in arb:
            raise SystemExit(f'duplicate {key} in {path}')
        arb[key] = value[lang]
        if lang == 'fr':
            meta = collections.OrderedDict(description=value['desc'])
            if 'placeholders' in value:
                meta['placeholders'] = value['placeholders']
            arb['@' + key] = meta
    save(path, arb)

path = 'lib/l10n/mg_review_status.json'
status = load(path)
for key in spec:
    status['strings'][key] = 'needs_review'
save(path, status)
print('added', len(spec))
