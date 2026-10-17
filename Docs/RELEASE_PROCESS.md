# XenQuest - Development and Release Workflow

## One-time setup

1. Keep your most recently **working** complete XenQuest addon ZIP safe. Do not delete your `.git` folder if the current project is already a Git repository.
2. Inside `C:\Users\crown\Documents\Coding-Projects\XenQuest`, extract the addon ZIP so you have `XenQuest\XenQuest.toc` under the project root. **Do not** place `Versions`, `Tools`, or other development files inside that addon folder.
3. Extract the accompanying development toolkit ZIP into the project root, so `Tools` is a sibling of `XenQuest`.
4. Double-click `01-Configure.cmd` and choose the `Interface\AddOns` directory belonging to your active game client (previous Forever tests used `_classic_beta_`; confirm your own installation).
5. Double-click `02-Install-to-WoW.cmd`. It backs up the previous installed addon and mirrors the current project `XenQuest` folder into the game client. Type `/reload` in WoW.

## Every development change

- Edit and save source files **only** under `Coding-Projects\XenQuest\XenQuest`.
- Double-click `02-Install-to-WoW.cmd` to sync changes to WoW; then `/reload`.
- Avoid hand-editing the copy installed in `Interface\AddOns\XenQuest`, because the next sync replaces those edits.
- Save a Git commit after each confirmed feature or bugfix. Local ZIP files are not Git history.

## Packaging a local test version

1. Set `## Version: 0.2.13-beta` (or your next intended version) inside `XenQuest\XenQuest.toc`.
2. Double-click `03-Package-Version.cmd`.
3. Find `Versions\XenQuest-v0.2.13-beta-LOCAL-TEST.zip` alongside its `.sha256.txt` file.
4. This ZIP has exactly one top-level `XenQuest/` folder ready for extracting into `Interface\AddOns`.
5. If a ZIP of the same version already exists, the script refuses to overwrite it. Intentionally rebuild it with `powershell.exe -ExecutionPolicy Bypass -File .\Tools\Build-Release.ps1 -Force` if needed.

## Publishing to GitHub / CurseForge

- **Current block:** The existing source archive includes QuestieDB-derived `Data/BulkGuidance.lua` and `Data/QuestContext.lua`, for which redistribution terms were previously identified as unresolved. Treat all generated ZIPs as local-only until you have documented permission or a compliant licensing approach. This is not a substitute for legal review.
- After resolving the source-data issue, record the evidence and clearance decision in `Docs\DATA_RIGHTS_CLEARANCE.txt` with the exact line `CLEARED=YES` (after also removing any outdated NOT CLEARED notice from the addon). This file is a human-confirmed record, **not** an automated determination of legal rights.
- The build script only creates a ZIP named without `LOCAL-TEST` when run intentionally with `-Public`, and it refuses while the review notice or missing clearance exists.
- Example: `powershell.exe -ExecutionPolicy Bypass -File .\Tools\Build-Release.ps1 -Public`.
- Test the precise public ZIP inside WoW before uploading it.
- Tag your source commit with the matching version (e.g., `v0.2.13-beta`), attach the ZIP in GitHub Releases, and upload that **same** ZIP to CurseForge.

## Git repository and backups

- The Git repo should be the **outer project folder** (the one holding `XenQuest`, `Tools` and `Docs`). The game-loadable addon lives in the `XenQuest` subfolder. `Versions` and `Backups` are intentionally excluded from Git.
- Existing GitHub repositories may have the addon directly at repository root. Moving it to `XenQuest/` changes repository layout; review and commit this restructuring deliberately. Do not force-push or delete existing Git history.
- If the old workspace did not have `.git`, **clone your existing GitHub repository first** rather than overwriting history with a fresh unrelated `git init`.
- Saving the zipped versions locally provides backups, but Git tags/commits are what let you compare or reverse individual changes.

## Safeguards

- Development install uses `robocopy /MIR` and **deletes** files in the target `Interface\AddOns\XenQuest` folder that are absent from the project source. It creates a timestamped ZIP backup of the previously installed addon by default. It does not touch `WTF` saved variables.
- Keep your QuestieDB master archive / generated research inputs outside `XenQuest/` and outside public packaged versions. `LocalData/` is Git-ignored by default.
- Review `/XenQuest/XenQuest.toc` when adding new Lua modules: the addon only loads Lua files listed there.
- The scripts use Windows PowerShell 5.1 features. They do not automatically publish anything online.
