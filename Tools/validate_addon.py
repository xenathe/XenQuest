#!/usr/bin/env python3
"""Validate Git-tracked XenQuest source and optionally build a CI-only ZIP.

The in-game installer/packager deliberately add locally generated QuestieDB
modules that are not tracked by Git. This CI validator instead uses only
`git ls-files` so a clean checkout is self-consistent and third-party content
can't leak into CI artifacts. Does not publish a release.
"""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import zipfile

ADDON = "XenQuest"
TOC = "XenQuest/XenQuest.toc"
BLOCKED_NAMES = {"WorldMap.lua", "BulkGuidance.lua", "QuestContext.lua"}
MANDATORY_LUA = {
    "QuestItems.lua",
    "QuestItemButtons.lua",
    "BlizzardUI.lua",
    "Navigation.lua",
    "Data/QuestGuidance.lua",
    "ObjectiveGuidance.lua",
    "Core.lua",
}


class ValidationError(RuntimeError):
    pass


def git_tracked(root: Path) -> list[str]:
    cp = subprocess.run(
        ["git", "ls-files", "-z", "--cached"],
        cwd=root, capture_output=True, check=True,
    )
    return sorted({p.decode("utf-8") for p in cp.stdout.split(b"\0") if p})


def _safe_path(relative: str) -> bool:
    p = PurePosixPath(relative)
    return (
        bool(relative)
        and "\\" not in relative
        and not p.is_absolute()
        and len(p.parts) > 0
        and all(part not in {".", ".."} for part in p.parts)
        and str(p) == relative
    )


def validate(root: Path, tracked: list[str]) -> tuple[list[str], str]:
    errors: list[str] = []
    tracked_set = set(tracked)

    if TOC not in tracked_set:
        errors.append(f"Missing Git-tracked {TOC}")

    lowered: set[str] = set()
    for rel in tracked:
        if not _safe_path(rel):
            errors.append(f"Unsafe tracked path: {rel}")
        lower = rel.lower()
        if lower in lowered:
            errors.append(f"Case-insensitive file collision: {rel}")
        lowered.add(lower)
        name = PurePosixPath(rel).name
        if name.lower() in {b.lower() for b in BLOCKED_NAMES}:
            errors.append(f"Blocked file committed: {rel}")
        if rel.startswith(ADDON + "/"):
            if lower.endswith((".zip", ".bak", ".tmp", ".pyc")):
                errors.append(f"Generated/backup file committed inside addon: {rel}")
            if not (root / rel).is_file():
                errors.append(f"Tracked file not present on disk: {rel}")

    if errors:
        raise ValidationError("\n".join(errors))

    content = (root / TOC).read_text(encoding="utf-8-sig")
    version_match = re.search(r"^##\s*Version:\s*([\w.\-]+)\s*$", content, re.M)
    if not version_match:
        errors.append("TOC missing '## Version:'")
        version = "unknown"
    else:
        version = version_match.group(1)
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\d*)?", version):
            errors.append(f"Invalid addon version: {version}")

    loaded = []
    for row in content.splitlines():
        entry = row.strip()
        if not entry or entry.startswith("#"):
            continue
        if not entry.lower().endswith(".lua") or not _safe_path(entry):
            errors.append(f"Invalid TOC entry: {entry}")
            continue
        if entry in loaded:
            errors.append(f"Duplicate TOC entry: {entry}")
        loaded.append(entry)
        if f"{ADDON}/{entry}" not in tracked_set:
            errors.append(f"TOC references missing/untracked Lua: {entry}")
    for entry in sorted(MANDATORY_LUA - set(loaded)):
        errors.append(f"Mandatory Lua not loaded by TOC: {entry}")
    if not loaded:
        errors.append("No Lua modules listed in TOC")

    addon_files = sorted(p for p in tracked if p.startswith(ADDON + "/"))
    if errors:
        raise ValidationError("\n".join(errors))
    return addon_files, version


def smoke_zip(root: Path, addon_files: list[str], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as arc:
        for p in addon_files:
            arc.write(root / p, arcname=p)
    with zipfile.ZipFile(path) as arc:
        names = set(arc.namelist())
        if arc.testzip():
            raise ValidationError("ZIP integrity failed")
        if names != set(addon_files) or TOC not in names:
            raise ValidationError("ZIP entries do not match Git-tracked addon files")
        if any(not n.startswith("XenQuest/") or "\\" in n for n in names):
            raise ValidationError("Invalid ZIP root or path separator")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip-out", type=Path, help="Generate/test a CI-only ZIP at this path")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        tracked = git_tracked(root)
        addon_files, version = validate(root, tracked)
        print(f"PASS: XenQuest {version}, {len(addon_files)} tracked addon files")
        if args.zip_out:
            smoke_zip(root, addon_files, args.zip_out.resolve())
            print(f"PASS: ZIP layout/integrity: {args.zip_out}")
        print("PASS: No WorldMap module or excluded guidance data is committed")
        return 0
    except (OSError, subprocess.CalledProcessError, ValidationError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
