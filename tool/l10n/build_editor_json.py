"""Writes the native editors' string tables from tool/l10n/editor_strings.py
and reports tr("...") keys in the Kotlin/Swift code that have no entry.

    python tool/l10n/build_editor_json.py
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.dirname(__file__))
from editor_strings import E, LANGS  # noqa: E402

out = {lang: {en: row[lang] for en, row in E.items() if row[lang] != en} for lang in LANGS}
for rel in ['android/app/src/main/assets/l10n/editor.json', 'ios/Runner/Editor/AdGagL10n/editor.json']:
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)

# placeholders must survive translation
PH = re.compile(r'\{\d\}')
bad = [(en, lang) for en, row in E.items() for lang in LANGS if sorted(PH.findall(en)) != sorted(PH.findall(row[lang]))]
for en, lang in bad:
    print('PLACEHOLDER MISMATCH', lang, en)

TR = re.compile(r'\btr\(\s*"((?:[^"\\]|\\.)*)"')
used = set()
files = glob.glob(os.path.join(ROOT, 'android/app/src/main/kotlin/com/adgag/adgag/editor/*.kt')) + \
    glob.glob(os.path.join(ROOT, 'ios/Runner/Editor/*.swift'))
for p in files:
    with open(p, encoding='utf-8') as f:
        for m in TR.finditer(f.read()):
            used.add(m.group(1).replace('\\"', '"'))
missing = sorted(k for k in used if k not in E)
for k in missing:
    print('MISSING', repr(k))
print(f'{len(E)} strings x {len(LANGS)} languages; {len(used)} tr() keys in code, {len(missing)} missing')
sys.exit(1 if missing or bad else 0)
