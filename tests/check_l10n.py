"""Validates the l10n file against the settings definitions.

Requires: pip install pyyaml

It checks four things, every one of which has already caught a real bug:
  1. the file is valid YAML (an unquoted colon inside a description breaks the WHOLE file,
     and with it the settings page),
  2. every setting and every group has both a name and a description key,
  3. no keys are left orphaned after a setting is removed,
  4. previews use ICU syntax {name} and NOT %{name} (the latter renders literally as "%32"),
     and their placeholders match what slider.lua actually supplies.
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)  # the mod directory is the repository root
L10N = os.path.join(MOD, "l10n", "SanctuaryFromUnarmored", "en.yaml")
CONFIG = os.path.join(MOD, "scripts", "sanctuary_from_unarmored", "config.lua")
SLIDER = os.path.join(MOD, "scripts", "sanctuary_from_unarmored", "slider.lua")

failures = []


def report(ok, message):
    print(("OK   " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


raw = open(L10N, encoding="utf-8").read()
try:
    data = yaml.safe_load(raw)
    report(True, f"YAML valid, {len(data)} keys")
except yaml.YAMLError as exc:
    report(False, f"YAML does not parse: {exc}")
    sys.exit(1)

config = open(CONFIG, encoding="utf-8").read()
slider = open(SLIDER, encoding="utf-8").read()

needed = set()
for key in re.findall(r"(?:number|checkbox|slider|button)\('(\w+)'", config):
    needed.update({key, key + "Description"})
for group in re.findall(r"name = '(\w+)',", config):
    needed.update({group, group + "Description"})
# Labels a renderer looks up by itself, named in the setting's argument (the button's captions).
needed.update(re.findall(r"(?:offLabel|onLabel|onNote) = '(\w+)'", config))
# pageDescription deliberately does not exist - the page opens straight into the options,
# and `description` is optional in registerPage.
needed.add("pageName")

previews = {k for k in data if k.startswith("preview_")}
# Runtime messages (ui.showMessage) - checked against the scripts rather than the settings.
messages = {k for k in data if k.startswith("msg_")}
scripts = os.path.join(MOD, "scripts", "sanctuary_from_unarmored")
used_messages = set()
for name in os.listdir(scripts):
    source = open(os.path.join(scripts, name), encoding="utf-8").read()
    used_messages.update(re.findall(r"'(msg_\w+)'", source))
report(
    messages == used_messages,
    f"messages in l10n vs used in scripts: {sorted(messages ^ used_messages) or 'match'}",
)

report(not (needed - set(data)), f"missing keys: {sorted(needed - set(data)) or 'none'}")
report(
    not (set(data) - needed - previews - messages),
    f"orphaned keys: {sorted(set(data) - needed - previews - messages) or 'none'}",
)

bad = [k for k, v in data.items() if isinstance(v, str) and "%{" in v]
report(not bad, f"%{{...}} placeholders instead of {{...}}: {bad or 'none'}")

def balanced_table(text, open_index):
    """Returns the body of the Lua table starting at `open_index`, counting braces.

    A naive regex is not enough here: the `npc` scenario contains a nested table
    `{ isPlayer = false }`, and a sloppy match pulled its keys in as if they were
    placeholders.
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
    """Top-level `name =` keys only, ignoring nested tables."""
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


# What slider.lua actually supplies to each preview.
supplied = {}
for header in re.finditer(r"return '(preview_\w+)',\s*\{", slider):
    name = header.group(1)
    supplied[name] = top_level_keys(balanced_table(slider, header.end() - 1))

for key in sorted(previews):
    used = set(re.findall(r"\{(\w+)\}", data[key]))
    have = supplied.get(key)
    if have is None:
        report(False, f"{key}: no scenario in slider.lua")
    else:
        report(used == have, f"{key}: placeholders {sorted(used)} vs supplied {sorted(have)}")

for key in sorted(supplied):
    if key not in data:
        report(False, f"{key}: scenario in slider.lua with no text in l10n")

print()
print("L10N OK" if not failures else f"FAILURES: {len(failures)}")
sys.exit(0 if not failures else 1)
