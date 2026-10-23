#!/usr/bin/env python3
"""Malagasy review spreadsheet (P-4).

  python3 tool/mg_sheet.py export eripoo-malagasy.xlsx

Sheet "Interface": lib/l10n/app_mg.arb; sheet "Contenu": every localized
text of content/*.yaml. The reviewer edits only the "Malagasy" and
"Statut" columns. Re-import: to be written when the first reviewed file
comes back (keys and locations make it mechanical).
"""
import json
import re
import sys
from pathlib import Path

import yaml
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parent.parent
L10N = ROOT / 'lib/l10n'
CONTENT = ROOT / 'content'
PLACEHOLDER = re.compile(r'\{[a-zA-Z0-9_]+\}')


def content_texts():
    """(file, pointer, node) for each localized text, in document order."""
    for path in sorted(CONTENT.rglob('*.yaml')):
        rel = path.relative_to(CONTENT).as_posix()
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))

        def walk(node, pointer):
            if isinstance(node, dict):
                if isinstance(node.get('fr'), str):
                    yield rel, pointer, node
                    return
                for k, v in node.items():
                    yield from walk(v, pointer + [str(k)])
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    yield from walk(v, pointer + [str(i)])

        yield from walk(doc, [])


def export(out):
    fr = json.loads((L10N / 'app_fr.arb').read_text(encoding='utf-8'))
    en = json.loads((L10N / 'app_en.arb').read_text(encoding='utf-8'))
    mg = json.loads((L10N / 'app_mg.arb').read_text(encoding='utf-8'))
    status = json.loads(
        (L10N / 'mg_review_status.json').read_text(encoding='utf-8'))['strings']
    wb = Workbook()
    head = ['Clé (ne pas modifier)', 'Français', 'Anglais', 'Malagasy',
            'Statut', 'Contexte / variables à garder']
    ws = wb.active
    ws.title = 'Interface'
    ws.append(head)
    for key, text in fr.items():
        if key.startswith('@'):
            continue
        desc = (fr.get('@' + key) or {}).get('description', '')
        keep = ' '.join(sorted(set(PLACEHOLDER.findall(text))))
        note = ' — '.join(x for x in [desc, f'Garder : {keep}' if keep else ''] if x)
        ws.append([key, text, en.get(key, ''), mg.get(key, ''),
                   status.get(key, 'needs_review'), note])
    wc = wb.create_sheet('Contenu')
    wc.append(['Emplacement (ne pas modifier)', 'Français', 'Anglais',
               'Malagasy', 'Statut', 'Contexte'])
    for rel, pointer, node in content_texts():
        st = (node.get('status') or {}).get('mg', 'machine_draft')
        wc.append([f'{rel}#{"/".join(pointer)}', node['fr'], node.get('en', ''),
                   node.get('mg', ''), st, ''])
    for sheet in (ws, wc):
        widths = [34, 50, 50, 60, 16, 40]
        for i, w in enumerate(widths):
            sheet.column_dimensions['ABCDEF'[i]].width = w
        for cell in sheet[1]:
            cell.font = Font(bold=True)
        for row in sheet.iter_rows(min_row=2):
            for cell in row:
                cell.alignment = Alignment(wrap_text=True, vertical='top')
            row[3].fill = PatternFill('solid', fgColor='FFF7D6')
        sheet.freeze_panes = 'B2'
        dv = DataValidation(type='list',
                            formula1='"reviewed,needs_review,machine_draft"')
        sheet.add_data_validation(dv)
        dv.add(f'E2:E{sheet.max_row}')
    readme = wb.create_sheet('Mode d\'emploi', 0)
    for line in [
        'Relecture du malagasy — Eripoo',
        '',
        'Corrigez uniquement la colonne « Malagasy » (fond jaune).',
        'Une fois un texte relu et juste, mettez « reviewed » dans « Statut ».',
        'Gardez telles quelles les variables entre accolades, ex. {count} ou {name}.',
        'Ne modifiez pas la première colonne, n\'ajoutez ni ne supprimez de lignes.',
        'Onglet « Interface » : boutons, menus, messages de l\'application.',
        'Onglet « Contenu » : quêtes, missions, outils, textes légaux.',
        'Renvoyez le fichier : il est réimporté automatiquement et vérifié.',
    ]:
        readme.append([line])
    readme.column_dimensions['A'].width = 100
    readme['A1'].font = Font(bold=True, size=14)
    wb.save(out)
    print(f'{ws.max_row - 1} interface strings, {wc.max_row - 1} content texts -> {out}')


def main():
    if len(sys.argv) == 3 and sys.argv[1] == 'export':
        export(sys.argv[2])
    else:
        sys.exit('usage: mg_sheet.py export <file.xlsx>')


if __name__ == '__main__':
    main()
