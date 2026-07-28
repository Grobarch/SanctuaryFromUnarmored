"""Runs test_formula.lua on a real Lua interpreter.

Requires: pip install lupa

No stubs are needed - formula.lua has no engine dependencies, so the mod's ORIGINAL file is
what gets executed here, not a copy of it.
"""
import os
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.dirname(HERE)  # the mod directory is the repository root

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().MOD_ROOT = MOD_ROOT.replace("\\", "/")

with open(os.path.join(HERE, "test_formula.lua"), encoding="utf-8") as handle:
    source = handle.read()

try:
    lua.execute(source)
except SystemExit as exc:
    sys.exit(exc.code)
