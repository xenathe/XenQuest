# Offline validation for XenQuest

Double-click `04-Validate.cmd` in the project root. No GitHub Actions or subscription is needed.

The launcher runs:
1. All Python unit tests under `Tests/test_*.py`.
2. The existing Git-tracked addon / TOC / blocked-data validator.
3. A temporary ZIP integrity test. **No** release archive is created.
4. Lua 5.1 syntax checking of **all** addon Lua files (including local guidance datasets) **if** `luac` 5.1 is installed.

If Lua 5.1 is absent the result will be **PARTIAL PASS**, not a claim that syntax passed. Optional: point the checker at your own trusted Lua 5.1 compiler using `set XENQUEST_LUAC=C:\path\to\luac.exe` in the same Command Prompt before running the launcher, or `04-Validate.cmd --luac "C:\path\to\luac.exe"`. To require it, run `04-Validate.cmd --require-lua`.

Tests don't install the addon, create a public release, alter the source, or push any Git commits. To test in-game, continue using `02-Install-to-WoW.cmd`. To produce a complete *local* addon ZIP, use `03-Package-Version.cmd`.

The temporary CI ZIP validates *Git-tracked* source only. It intentionally does not contain local third-party-derived `Data/BulkGuidance.lua` or `Data/QuestContext.lua` files. Those are still subject to the outstanding public redistribution review.

The GitHub Actions workflow can be disabled in the repository's **Actions** tab without disabling Git commits/pushes.
