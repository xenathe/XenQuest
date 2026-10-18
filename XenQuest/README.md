# XenQuest — v0.2.13-beta (native-only edition)

A lightweight WoW Forever quest tracker with custom themes, scrollable zone-grouped objectives, quest timers, quest-item shortcuts, movable isometric navigation and gold quest-target swords.

## Getting started

Extract the `XenQuest/` folder into your client's `Interface/AddOns/` directory. Use `/xq` for settings.

### Native quest learning

Run `/xq learn on` to enable learning quest-to-NPC relationships from client-supplied typed quest tooltip lines; `/xq learn status` shows stored quest count, and `/xq learn off` pauses future learning. Discoveries persist locally in `XenQuestDB`. Gold swords can show on supported nameplates for identified active objectives. No group sharing or external uploading occurs.

The old QuestieDB-derived bulk guidance, reference summaries and NPC mapping files are not shipped. New installations therefore have much lower quest-specific guidance coverage until the player discovers relationships. Native learning does not assume that a mob drops an item just because its tooltip references a quest.

Object discovery (e.g. ground crates) is not yet implemented. NPC data can be unavailable when WoW marks it restricted, particularly inside instances or combat. The addon skips inaccessible identities.

Other slash commands: `/xq all`, `/xq tracked`, `/xq guide status`, `/xq probe target`, `/xqmarkers status`.

## Custom fonts

The shipped addon intentionally does not include `Media/custom.ttf`. You can provide your own font file at that path; otherwise XenQuest uses built-in WoW fonts.

## Data provenance and support

See [`DATA_PROVENANCE.md`](DATA_PROVENANCE.md), [`RELEASE_NOTES.md`](RELEASE_NOTES.md) and the MIT `LICENSE` for original code. Texture and third-party asset rights should be independently checked before distributing.

Bugs and feedback: https://github.com/xenathe/XenQuest / https://discord.gg/96UKh6AeAN
