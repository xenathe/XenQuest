#!/usr/bin/env python3
"""XenQuest's offline, no-GitHub-Actions, one-click validator.

Runs all Python unit tests, validates tracked addon files/TOC and tests a
throwaway ZIP. If an actual Lua 5.1 bytecode compiler is available, also
syntax-checks ALL local addon Lua files (including Git-ignored guidance data).
The temporary test ZIP is deleted and no source files are modified.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "XenQuest"
LUA51_BANNER = re.compile(r"\bLua\s+5\.1(?:\D|$)", re.IGNORECASE)


def lua51_banner(value: str) -> bool:
    """Only trust an actual Lua 5.1 compiler, not a 5.2+ parser."""
    return bool(LUA51_BANNER.search(value))


def addon_lua_files(addon: Path) -> list[Path]:
    return sorted(p for p in addon.rglob("*.lua") if p.is_file()) if addon.is_dir() else []


def candidate_compilers(explicit: str | None = None) -> list[str]:
    if explicit:
        return [explicit]
    if os.getenv("XENQUEST_LUAC"):
        return [os.environ["XENQUEST_LUAC"]]
    return ["luac5.1.exe", "luac5.1", "luac51.exe", "luac51", "luac.exe", "luac"]


def find_lua51_compiler(explicit: str | None = None) -> tuple[str | None, str]:
    observations: list[str] = []
    for candidate in candidate_compilers(explicit):
        cmd = shutil.which(candidate)
        if not cmd and Path(candidate).is_file():
            cmd = str(Path(candidate).resolve())
        if not cmd:
            continue
        try:
            cp = subprocess.run([cmd, "-v"], capture_output=True, text=True, timeout=10)
            banner = (cp.stdout + " " + cp.stderr).strip()
        except (OSError, subprocess.TimeoutExpired) as exc:
            observations.append(f"{candidate}: {exc}")
            continue
        if cp.returncode == 0 and lua51_banner(banner):
            return cmd, banner.splitlines()[0] if banner else "Lua 5.1"
        observations.append(f"{candidate}: {banner[:120] or 'unknown version'}")
    return None, "; ".join(observations)


def run_step(title: str, command: list[str]) -> bool:
    print(f"\n=== {title} ===", flush=True)
    try:
        cp = subprocess.run(command, cwd=ROOT, check=False)
    except OSError as exc:
        print(f"FAIL: couldn't start check: {exc}", flush=True)
        return False
    if cp.returncode:
        print(f"FAIL: {title} (exit code {cp.returncode})", flush=True)
        return False
    print(f"PASS: {title}", flush=True)
    return True


def lua_syntax_check(compiler: str) -> bool:
    print("\n=== Lua 5.1 syntax (including local guidance files) ===", flush=True)
    sources = addon_lua_files(ADDON)
    if not sources:
        print("FAIL: No addon Lua files found in XenQuest/", flush=True)
        return False
    failures = []
    for file in sources:
        try:
            cp = subprocess.run([compiler, "-p", str(file)], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
            if cp.returncode:
                failures.append((file, (cp.stdout + cp.stderr).strip()))
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append((file, str(exc)))
    for file, reason in failures:
        print(f"FAIL: {file.relative_to(ROOT)}\n  {reason}", flush=True)
    if failures:
        print(f"FAIL: {len(failures)} of {len(sources)} Lua file(s) failed syntax checking.")
        return False
    print(f"PASS: {len(sources)} local Lua files compile with Lua 5.1", flush=True)
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luac", help="Full path to a Lua 5.1 luac.exe compiler")
    parser.add_argument("--require-lua", action="store_true",
                        help="Fail rather than skip the syntax check when Lua 5.1 isn't installed")
    args = parser.parse_args(argv)
    print("XENQUEST - LOCAL VALIDATION (no GitHub Actions; no publishing)", flush=True)
    print(f"Project: {ROOT}", flush=True)

    success = True
    # Discover future Python tests automatically, not only today's seven tests.
    success = run_step("Python unit tests", [sys.executable, "-B", "-m", "unittest",
                                                 "discover", "-s", "Tests", "-p", "test_*.py", "-v"]) and success

    # Temporary smoke-package; unlike 03-Package-Version.cmd it NEVER creates
    # a real version archive or includes local Git-ignored third-party data.
    with TemporaryDirectory(prefix="xenquest-validation-") as tmp:
        smoke = str(Path(tmp) / "XenQuest-CI-check.zip")
        success = run_step("Tracked source, TOC and temporary ZIP", [sys.executable, "-B",
                            "Tools/validate_addon.py", "--zip-out", smoke]) and success

    compiler, details = find_lua51_compiler(args.luac)
    lua_skipped = compiler is None
    if compiler:
        print(f"Lua compiler: {compiler} ({details})", flush=True)
        success = lua_syntax_check(compiler) and success
    else:
        print("\n=== Lua 5.1 syntax ===", flush=True)
        print("SKIPPED: no verified Lua 5.1 luac executable was found.", flush=True)
        if details:
            print(f"Found but not usable: {details}", flush=True)
        print("To enable it later, install Lua 5.1's luac.exe and put it on PATH,", flush=True)
        print('or set XENQUEST_LUAC to its full path before running 04-Validate.cmd.', flush=True)
        if args.require_lua or args.luac or os.getenv("XENQUEST_LUAC"):
            success = False
            print("FAIL: Lua 5.1 syntax checking was explicitly requested.", flush=True)

    print("\n" + "=" * 59, flush=True)
    if not success:
        print("RESULT: FAILED - fix the errors above before committing.", flush=True)
        return 1
    if lua_skipped:
        print("RESULT: PARTIAL PASS - structure/tests pass; Lua syntax NOT checked.", flush=True)
    else:
        print("RESULT: PASS - tests, structure, ZIP and Lua 5.1 syntax.", flush=True)
    print("No release was created, no file was pushed and no addon files changed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
