# XenQuest data provenance — native-only public candidate

This distributable ZIP deliberately omits the three locally generated QuestieDB-derived modules:

- `Data/BulkGuidance.lua`
- `Data/QuestContext.lua`
- `Data/TargetMarkerData.lua`

It does **not** rely on, bundle or claim permission to redistribute those source datasets. The release build uses an explicit allowlist and checks the final ZIP for excluded files. The development workspace may still contain these files for separate private work; they are never part of this native-only ZIP.

Included `Data/QuestGuidance.lua` contains five hand-authored, client-tested quest corrections from XenQuest's WoW Forever playtesting history. Unverified legacy 'Zenn's Bidding' hints have been removed pending independent confirmation.

At runtime, XenQuest reads the player's current quest log and native typed NPC tooltip quest lines (when WoW exposes them), matches active objectives, and stores findings only in `XenQuestDB` SavedVariables. These new observations are local to each installation. No automatic global sharing, uploads or third-party data import.

`QuestItems.lua` has an empty hardcoded verified-item map; its native bag/quest item APIs do not depend on QuestieDB. This build excludes the bundled optional Poppins font because a matching redistributable licence notice was not supplied. Users may install their own font.

This is a code/data audit of the three known imported databases, not a legal certification of all included artwork. Project maintainers should confirm authorship or redistribution rights for existing `Media/*.tga` assets and any other third-party assets before a public upload.
