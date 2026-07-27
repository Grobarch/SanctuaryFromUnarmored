"""Walidacja l10n wzgledem definicji ustawien.

Wymaga: pip install pyyaml

Sprawdza cztery rzeczy, z ktorych kazda juz raz cos zlapala:
  1. plik jest poprawnym YAML-em (nieocytowany dwukropek w opisie wywala CALY plik,
     a wraz z nim strone ustawien),
  2. kazde ustawienie i kazda grupa ma swoj klucz nazwy i opisu,
  3. nie ma kluczy osieroconych po usunietych ustawieniach,
  4. podglady uzywaja skladni ICU {name} - NIE %{name} (to drugie renderuje sie jako "%32"),
     a ich placeholdery zgadzaja sie z tym, co faktycznie podaje slider.lua.
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)  # katalog moda = korzen repo
L10N = os.path.join(MOD, "l10n", "UnarmoredDodge", "en.yaml")
CONFIG = os.path.join(MOD, "scripts", "unarmored_dodge", "config.lua")
SLIDER = os.path.join(MOD, "scripts", "unarmored_dodge", "slider.lua")

failures = []


def report(ok, message):
    print(("OK   " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


raw = open(L10N, encoding="utf-8").read()
try:
    data = yaml.safe_load(raw)
    report(True, f"YAML poprawny, kluczy: {len(data)}")
except yaml.YAMLError as exc:
    report(False, f"YAML nie parsuje sie: {exc}")
    sys.exit(1)

config = open(CONFIG, encoding="utf-8").read()
slider = open(SLIDER, encoding="utf-8").read()

needed = set()
for key in re.findall(r"(?:number|checkbox|slider)\('(\w+)'", config):
    needed.update({key, key + "Description"})
for group in re.findall(r"name = '(\w+)',", config):
    needed.update({group, group + "Description"})
# pageDescription celowo nie istnieje - strona zaczyna sie od razu od opcji, a `description`
# w registerPage jest opcjonalne.
needed.add("pageName")

previews = {k for k in data if k.startswith("preview_")}

report(not (needed - set(data)), f"brakujace klucze: {sorted(needed - set(data)) or 'brak'}")
report(
    not (set(data) - needed - previews),
    f"osierocone klucze: {sorted(set(data) - needed - previews) or 'brak'}",
)

bad = [k for k, v in data.items() if isinstance(v, str) and "%{" in v]
report(not bad, f"placeholdery %{{...}} zamiast {{...}}: {bad or 'brak'}")

def balanced_table(text, open_index):
    """Zwraca wnetrze tabeli Lua zaczynajacej sie na `open_index`, liczac nawiasy.

    Naiwny regex tu nie wystarcza: scenariusz `npc` zawiera zagniezdzona tabele
    `{ isPlayer = false }` i niedokladne dopasowanie wciagalo jej klucze jako
    rzekome placeholdery.
    """
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index + 1 : i]
    return ""


def top_level_keys(body):
    """Klucze `nazwa =` tylko z pierwszego poziomu tabeli."""
    keys, depth = set(), 0
    for match in re.finditer(r"[{}]|(\w+)\s*=", body):
        token = match.group(0)
        if token == "{":
            depth += 1
        elif token == "}":
            depth -= 1
        elif depth == 0 and match.group(1):
            keys.add(match.group(1))
    return keys


# Co slider.lua faktycznie podaje do kazdego podgladu.
supplied = {}
for header in re.finditer(r"return '(preview_\w+)',\s*\{", slider):
    name = header.group(1)
    supplied[name] = top_level_keys(balanced_table(slider, header.end() - 1))

for key in sorted(previews):
    used = set(re.findall(r"\{(\w+)\}", data[key]))
    have = supplied.get(key)
    if have is None:
        report(False, f"{key}: brak scenariusza w slider.lua")
    else:
        report(used == have, f"{key}: placeholdery {sorted(used)} vs podawane {sorted(have)}")

for key in sorted(supplied):
    if key not in data:
        report(False, f"{key}: scenariusz w slider.lua bez tekstu w l10n")

print()
print("L10N OK" if not failures else f"BLEDY: {len(failures)}")
sys.exit(0 if not failures else 1)
