"""Tests for the Git-safe build validator (stdlib only)."""
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Tools"))
from validate_addon import MANDATORY_LUA, ValidationError, validate, smoke_zip


class ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        toc = "## Interface: 16001\n## Version: 0.2.12-beta\n" + "\n".join(sorted(MANDATORY_LUA)) + "\n"
        self.tracked = ["XenQuest/XenQuest.toc"]
        (self.root / "XenQuest").mkdir()
        (self.root / "XenQuest/XenQuest.toc").write_text(toc, encoding="utf-8")
        for p in MANDATORY_LUA:
            rel = "XenQuest/" + p
            dest = self.root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text("-- test\n", encoding="utf-8")
            self.tracked.append(rel)

    def test_valid_git_safe_addon(self):
        files, version = validate(self.root, self.tracked)
        self.assertEqual(version, "0.2.12-beta")
        self.assertEqual(len(files), len(MANDATORY_LUA) + 1)

    def test_local_untracked_guidance_is_ignored(self):
        (self.root / "XenQuest/Data/BulkGuidance.lua").write_text("-- local only")
        files, _ = validate(self.root, self.tracked)
        self.assertFalse(any("BulkGuidance" in p for p in files))

    def test_blocks_committed_guidance(self):
        with self.assertRaisesRegex(ValidationError, "Blocked file committed"):
            validate(self.root, self.tracked + ["XenQuest/Data/BulkGuidance.lua"])

    def test_blocks_world_map(self):
        with self.assertRaisesRegex(ValidationError, "Blocked file committed"):
            validate(self.root, self.tracked + ["XenQuest/WorldMap.lua"])

    def test_blocks_missing_toc_entry(self):
        toc = self.root / "XenQuest/XenQuest.toc"
        toc.write_text(toc.read_text() + "Missing.lua\n")
        with self.assertRaisesRegex(ValidationError, "missing/untracked Lua"):
            validate(self.root, self.tracked)

    def test_blocks_local_guidance_in_toc(self):
        toc = self.root / "XenQuest/XenQuest.toc"
        toc.write_text(toc.read_text() + "Data/QuestContext.lua\n")
        with self.assertRaisesRegex(ValidationError, "missing/untracked Lua"):
            validate(self.root, self.tracked)

    def test_smoke_zip_only_tracks_source(self):
        (self.root / "XenQuest/Data/QuestContext.lua").write_text("-- local only")
        files, _ = validate(self.root, self.tracked)
        out = self.root / "build.zip"
        smoke_zip(self.root, files, out)
        import zipfile
        with zipfile.ZipFile(out) as arc:
            self.assertNotIn("XenQuest/Data/QuestContext.lua", arc.namelist())
            self.assertIn("XenQuest/XenQuest.toc", arc.namelist())


if __name__ == "__main__":
    unittest.main()
