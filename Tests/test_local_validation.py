"""Small unit tests for XenQuest's offline validation launcher."""
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Tools"))
from validate_local import lua51_banner, addon_lua_files, candidate_compilers


class LocalValidationTests(unittest.TestCase):
    def test_accepts_lua_51(self):
        self.assertTrue(lua51_banner("Lua 5.1.5  Copyright (C) ..."))

    def test_rejects_incompatible_lua_versions(self):
        for banner in ["Lua 5.2.4", "Lua 5.3.6", "Lua 5.4.7", "LuaJIT 2.1", ""]:
            self.assertFalse(lua51_banner(banner))

    def test_explicit_compiler_is_not_silently_replaced(self):
        self.assertEqual(candidate_compilers("C:/Lua/luac.exe"), ["C:/Lua/luac.exe"])

    def test_checks_git_ignored_lua_too(self):
        with TemporaryDirectory() as td:
            addon = Path(td) / "XenQuest"
            (addon / "Data").mkdir(parents=True)
            (addon / "Core.lua").write_text("-- core")
            (addon / "Data/BulkGuidance.lua").write_text("-- locally ignored")
            (addon / "Data/not_lua.txt").write_text("no")
            self.assertEqual(len(addon_lua_files(addon)), 2)


if __name__ == "__main__":
    unittest.main()
