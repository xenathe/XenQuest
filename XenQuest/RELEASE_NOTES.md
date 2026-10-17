# XenQuest v0.2.12-beta — Intelligent Quest Guidance & Quality of Life

XenQuest takes a major step beyond basic quest tracking. This update introduces a local, data-driven guidance engine, a scrollable tracker for larger quest logs, streamlined quest interactions and a collection of important positioning fixes.

## New — Intelligent Objective Guidance

- Added helpful, context-aware objective descriptions for supported quests, including creature kills, item collection and interacting with quest objects.
- Preserved live quest counters, progress bars and completion effects when displaying longer descriptions.
- Added a large offline guidance catalogue generated from a WoW Forever quest-data snapshot: **5,179 quests analysed; 1,577 quests with enhanced-guidance candidates**.
- Included source-objective reference summaries for **4,535 quests**, visible by hovering a matching quest title.
- Identifies multiple possible enemy sources for supported collection objectives, including *The Everstill Bridge*'s Iron Pikes and Iron Rivets.
- Retains previously confirmed, Forever-specific corrections, including *The Stolen Tome* and *Rascally Rodents*.
- Checks both quest ID and quest title before applying bulk guidance, preventing incorrect instructions when clients use different quest records.
- Falls back to the original in-game objective text whenever no sufficiently supported enhanced description is available.
- Added optional guidance controls and an opt-in objective recorder (`/xq guide status`, `/xq guide record on`, `/xq guide record off`, `/xq guide inspect`).

**Coverage note:** 1,577 is the number of quests with *candidate* enhanced descriptions, not 1,577 individually player-verified quests. Not every quest can yet receive a more detailed instruction. Reference tooltips reflect imported source data and may differ from modified Forever quests.

## New — Scrollable Quest Tracker

- Scroll through large quest lists with the mouse wheel, including when hovering quest titles and other rows.
- Added a subtle scrollbar that appears only when content exceeds the available height.
- Corrected scrollbar direction so the thumb moves down when you scroll down.
- Refined the scrollbar with a proportional thumb and dragging support.
- Keeps the tracker bounded within the available screen area without overwriting saved placement.

## Improved — Quest Mouse Controls

- **Left-click any quest:** open that specific quest in Blizzard's quest log, including completed quests.
- **Right-click a quest:** expand or collapse its objectives.
- **Left-click the quest marker:** toggle navigation to the quest.
- Improved right-button camera pass-through on non-interactive tracker areas where supported by the game client.

## Fixes & Polishing

- Fixed longer objective counters such as `10/10` wrapping or overlapping progress bars.
- Stabilised the tracker anchor when minimising, expanding or reloading the UI; no manual unlock/relock required.
- Added avoidance of visible right-side Blizzard action bars, including dynamic changes, without changing the saved position.
- Preserved automatic zone grouping, completion effects, timed quests, quest-item controls, themes and the 64-frame Gold/Ice isometric navigation artwork.

## Known Limitations

- Enhanced objective descriptions depend on the available Forever source data; some objectives will intentionally retain Blizzard's wording.
- Quest source associations are generated suggestions and may require further correction for modified/custom content.
- Right-click camera pass-through and action-bar positioning depend on what the active WoW client exposes; edge cases may remain.
- The **experimental Garrick-only nameplate skull marker is not included** in this update, pending further in-game validation.
- No experimental XenQuest World Map overlay is included.

## Release Information

- **Version:** `0.2.12-beta`
- **Release type:** Beta
- **Primary client:** World of Warcraft: Forever (`Interface 16001`)
- **Previous public version:** `0.2.11-beta`

## Support

Report problems or suggest features on the official [XenQuest Discord](https://discord.gg/96UKh6AeAN). Source repository: [xenathe/XenQuest](https://github.com/xenathe/XenQuest).

**Thanks for supporting XenQuest — happy questing!**
