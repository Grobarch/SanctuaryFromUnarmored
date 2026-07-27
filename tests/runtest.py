"""Uruchamia test_formula.lua na prawdziwym interpreterze Lua.

Wymaga: pip install lupa

Harness stubuje openmw.types i wykonuje ORYGINALNY formula.lua z ../UnarmoredDodge,
wiec testowany jest kod moda, a nie jego kopia.
"""
import os
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.dirname(HERE)  # katalog moda = korzen repo

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().MOD_ROOT = MOD_ROOT.replace("\\", "/")

with open(os.path.join(HERE, "test_formula.lua"), encoding="utf-8") as handle:
    source = handle.read()

try:
    lua.execute(source)
except SystemExit as exc:
    sys.exit(exc.code)
