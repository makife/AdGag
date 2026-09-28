"""Regenerates l10n/app_<lang>.arb from tool/l10n/strings.py.

    python tool/l10n/build_arb.py && flutter gen-l10n
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strings import LANGS, PLACEHOLDERS, S  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "l10n")

problems = []
for key, texts in S.items():
    wanted = set(PLACEHOLDERS.get(key, {}))
    for lang in LANGS:
        found = set(re.findall(r"\{(\w+)\}", texts[lang]))
        if found != wanted:
            problems.append(f"{key} [{lang}]: placeholders {sorted(found)} != declared {sorted(wanted)}")
if problems:
    print("\n".join(problems))
    sys.exit(1)

for lang in LANGS:
    arb = {"@@locale": lang}
    for key, texts in S.items():
        arb[key] = texts[lang]
        if lang == "en" and key in PLACEHOLDERS:
            arb["@" + key] = {"placeholders": {name: {"type": t} for name, t in PLACEHOLDERS[key].items()}}
    with open(os.path.join(OUT, f"app_{lang}.arb"), "w", encoding="utf-8") as f:
        json.dump(arb, f, ensure_ascii=False, indent=2)
        f.write("\n")
print(f"{len(S)} strings x {len(LANGS)} languages")
