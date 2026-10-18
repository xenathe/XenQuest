# XenQuest v0.2.13-beta — Quest Target Swords & Native Learning

XenQuest now helps you identify enemies relevant to your active quests and can learn useful quest-to-enemy relationships directly from World of Warcraft: Forever's own tooltip data. This update also polishes quest difficulty display, highlights elite quests, and improves navigation and compatibility.

## New — Quest Target Swords

- Added gold sword indicators above supported enemy nameplates when the enemy is relevant to an unfinished quest objective.
- Displays a sword above native-learned NPCs relevant to active unfinished objectives. A fresh installation learns relationships as players encounter enemies.
- Added controls for enabling markers, changing icon size, and choosing between marking all eligible enemies and closest-only where distance can be measured reliably.
- Markers stop appearing for finished objectives and do not target, attack, or interact with enemies automatically.

## New — Native Quest Learning (Experimental)

- Added an optional learning engine that reads supported **native WoW Forever quest tooltip information** and matches it against the player's active, unfinished objectives.
- Learned NPC/objective relationships are saved locally and can be reused for improved quest instructions and sword markers.
- Confirmed kill-objective improvements can update live, such as `Riverpaw Miner Slain` becoming `Kill Riverpaw Miner`.
- Uses strict quest/objective matching and does not invent item drop sources when the tooltip does not establish them.
- Includes `/xq learn on`, `/xq learn off`, `/xq learn target`, and `/xq learn status` for testing and control.
- Native-only data is the only source of NPC mappings shipped in this release; no QuestieDB-derived data files are included.

**Note:** Run `/xq learn on` to enable learning. This is an experimental local-learning feature, not a global shared database. Discovered knowledge is stored in the player's own SavedVariables and is not automatically transmitted to other XenQuest installations.

## New — Clearer Quest Difficulty & Elite Identification

- Quest levels now keep the selected XenQuest theme colour by default.
- Only the bracketed level turns red when a quest is five or more levels above the player's current level.
- Supported elite/group quests show a compact `(E)` after their title.
- Hovering an elite quest displays: *This is an Elite quest, form a party to complete it*.

## Improved — Navigation

- Added corpse-run guidance when the game provides a valid corpse location.
- Normal quest navigation resumes after resurrection.
- Existing movable isometric navigation and tracker interactions remain intact.

## Fixes & Compatibility

- Hardened quest target markers against restricted ("secret") NPC GUID/name/ID values to reduce errors in instances and combat.
- Improved the native tooltip diagnostic so a valid target without an open tooltip is reported accurately.
- Preserved zone grouping, completion effects, objective bars, quest-item shortcuts, themes, and scrollable tracker behaviour.

## Known Limitations

- Native learning currently focuses on supported NPC/quest relationships. Learning from quest objects such as ground crates is not yet implemented.
- Native learning requires readable quest metadata from the WoW Forever client. Some in-instance or combat data may be restricted.
- Certain collection objectives cannot safely identify their item source from a tooltip alone; XenQuest keeps the original wording when evidence is insufficient.
- Closest-only markers depend on available NPC distance information.
- Player discoveries are local. Community-wide automatic discovery sharing and a database manager are future ideas, not part of this release.

## Release Information

- **Proposed version:** `v0.2.13-beta`
- **Client:** World of Warcraft: Forever (`Interface 16001`)
- **Status:** Native-only release candidate; test the exact ZIP on WoW Forever before publication.
- **Baseline:** v0.2.12-beta development source.

**Redistribution notice for the release maintainer:** Do not upload a package containing the QuestieDB-derived `Data/BulkGuidance.lua`, `Data/QuestContext.lua` or `Data/TargetMarkerData.lua` while the necessary redistribution rights remain unresolved. Prepare and test a native-only public package, or wait for rights clearance. Remove this note from user-facing release text only after the actual package contents and rights have been verified.

## Support

Report bugs or quest-specific inaccuracies in the [XenQuest GitHub repository](https://github.com/xenathe/XenQuest), or join the [XenQuest Discord](https://discord.gg/96UKh6AeAN).

## Distribution data policy

This native-only edition excludes `Data/BulkGuidance.lua`, `Data/QuestContext.lua` and `Data/TargetMarkerData.lua`. Initial guidance coverage is lower than previous local development builds. Locally verified hand-authored quest corrections remain in `Data/QuestGuidance.lua`. The native learner stores discoveries in `XenQuestDB` SavedVariables, not a community server. No QuestieDB licence permission is presumed. See `DATA_PROVENANCE.md`.
