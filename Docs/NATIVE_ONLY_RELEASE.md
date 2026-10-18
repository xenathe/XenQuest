# Native-only v0.2.13-beta public release instructions

The development source may retain three QuestieDB-derived local datasets for historical/private testing. The public builder deliberately **excludes** them. Do not delete or rename them to trick the original publication guard.

## Replace project files

Back up the project first. Copy the `XenQuest/` and `Tools/` folders from this development patch into the outer project root, merging files and overwriting the matching ones. Retain the existing local datasets only in the developer environment; they are excluded from the native-only public build.

## Build on Windows, in VS Code PowerShell

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Tools\Build-Release.ps1 -Public -NativeOnly
```

Creates `Versions\XenQuest-v0.2.13-beta.zip` and its SHA256 file. It does not publish anything. If an earlier ZIP already exists and you intentionally want to replace it, append `-Force`.

Do **not** run `03-Package-Version.cmd` for the public ZIP; that deliberately creates a full local developer archive with imported data.

## Test the EXACT release archive

Exit WoW (recommended), then:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Tools\Test-NativePublic-Zip.ps1
```

This script validates the archived paths, creates a timestamped backup of the existing installed addon, replaces only `Interface/AddOns/XenQuest` from the exact public ZIP, and leaves `WTF` SavedVariables alone. It will not modify the development source. Start WoW or `/reload` after replacing.

**Important:** Do not run `02-Install-to-WoW.cmd` before verifying the release candidate: the ordinary developer installer restores your locally generated datasets and won't test the public ZIP.

### WoW Forever validation checklist

1. `/xq` opens settings, tracker renders and zone grouping, progress bars, timers, quest-item buttons, and elite hints still work.
2. Existing theme and navigation artwork load; corpse navigation returns to quest navigation after resurrection when the client provides corpse coordinates.
3. `/xq learn on` enables native discovery; hover/target a quest NPC on an unfinished objective and run `/xq learn status`.
4. Confirm a live objective like Riverpaw Miner Slain updates to Kill Riverpaw Miner, and gold swords appear above learned quest NPCs.
5. `/reload` then `/xq learn status`: learned associations persist in SavedVariables.
6. A fresh character/account with no SavedVariables should have **no imported quest guidance**. This is expected and must not be advertised as universal guidance coverage.
7. Change target/turn camera/enter combat, especially inside Deadmines: no secret-value errors or popup storm. A restricted identity should simply be skipped.
8. Confirm no missing image assets and no addon Lua errors. Test on the exact ZIP, not the developer install.

## Final pre-release requirements

- Review `XenQuest/DATA_PROVENANCE.md`. The three third-party datasets and optional custom font are explicitly excluded.
- Verify that `Media/*.tga` images are original/redistributable. Code/data filtering alone is **not** blanket copyright clearance.
- Run existing offline tests where possible. These are not a replacement for WoW Forever runtime validation.
- Update Git with new source modules, updated script and documentation (ensure `NativeLearning.lua`, `TooltipProbe.lua`, `TargetMarkers.lua` are tracked).
- Ensure `git status` contains no unpublished imported files; check the intended commit before tagging `v0.2.13-beta`.
- Publish the exact tested `Versions\XenQuest-v0.2.13-beta.zip` and paste `XenQuest/RELEASE_NOTES.md` to GitHub Releases.

The distribution-specific `-Public -NativeOnly` flag removes only the known imported datasets by strict allowlist. Running `-Public` without it **still blocks** until separate licensing permission is documented. No permission or clearance is falsely asserted by this native-only build.
