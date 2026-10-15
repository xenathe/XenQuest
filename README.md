# XenQuest
A lightweight, customisable quest tracker for World of Warcraft.

## 0.2.3-beta

- Keep incomplete quests above completed quests, preserving quest-log order within each group.
- Celebrate newly completed quests with a green shimmer and a 1.26-second bounce/glide, then leave their objectives collapsed. Right-click to expand or collapse; automatic collapse does not change saved manual choices.
- Retain quest rows through refreshes, handle removal and rapid completions, and finish animations safely when the tracker is hidden or minimized. Already completed quests do not replay the effect on reload.
- Show up to two 24-pixel quest-item icons beside the title, with native tooltips, counts, cooldowns and secure click-to-use actions. **Show quest item buttons** is enabled by default in settings.
- Hide Blizzard tracker roots and their mouse regions, with reversible state and native re-show hooks.
- Left-click a quest title to open that quest in the native log. Wrapped titles have their own hit region; marker tracking, item actions, right-click collapse and Shift-click sharing retain separate handlers.
- Display active quest countdowns beside their titles, including completed quests whose turn-in timer is still running.

Completion animation requires a stable quest ID and an observed incomplete-to-complete transition while the quest is displayed. Clients exposing only log indices still sort and collapse completed quests, without guessing completion transitions. Passing neighbours are briefly masked to prevent overlapping text while rows glide through the list.

Validation: `Tests/Completion.lua` runs the addon against a mock legacy UI and both quest-log API paths (Lua 5.1). Actual rendering, scroll clipping, native tracking and event timing still require in-game testing on WoW Forever (Interface 16001).

Run from the addon folder with `lua Tests/Completion.lua` using Lua 5.1. In game, complete quests near both ends of a scrolled list, complete several together, abandon one during the glide, resize/change fonts during movement, and hide or minimize the tracker before reopening it. Check the shimmer, neighbour masking, wrapped titles, marker tooltips and native map tracking. No Retail animation API or per-quest timer is used.

## Quest timers

Timed quests show their remaining time directly after the title, for example `Iverron's Antidote (4:59)`. Durations of an hour or more use `H:MM:SS`. The countdown shares the title's wrapping, click region and animation, leaving the marker and item-button areas intact. It remains visible when objectives are collapsed or complete, and disappears when the client removes the timer or quest.

Forever's `C_QuestLog.GetQuestTimers()` records are matched by `questID`, never by display order or timer-list position. Clients with `C_QuestLog.GetTimeAllowed` use its total and elapsed duration instead. Older selected-entry APIs use `GetQuestLogTimeLeft`, temporarily selecting each entry and restoring the original selection; this legacy fallback is withheld during combat. Forever's ID-based path does not change selection and continues during combat. No quest names, durations or special quest IDs are hardcoded.

Timer data refreshes with the existing tracker refresh (at most about 0.7 seconds between normal refreshes) and on `QUEST_TIMER_UPDATE`; no per-frame timer scans or saved countdowns are added. Run `lua Tests/QuestTimers.lua` with Lua 5.1 for mocked API, formatting, expiry, sorting, row reuse and compatibility checks. In game, accept Iverron's Antidote or another timed quest and compare the countdown with the native log, including after `/reload`, completion, collapse, combat and abandonment. Verify wrapped titles and item icons still fit. Actual Forever timer behavior requires in-game verification.

## Quest item quick-use

Detection first uses carried-bag quest-ID associations (`C_Container.GetContainerItemQuestInfo` or its legacy equivalent), requiring a positive `C_Item.GetItemSpell` / `GetItemSpell` result. Next it checks `GetQuestLogSpecialItemInfo` using the quest's current log index. Finally it consults `QuestItems.lua`'s numeric `Verified` mapping. Inventory ownership is required in every case; names and the quest-item bag flag alone are never sufficient. A native special item may remain visible after completion only when the client explicitly requests it.

The fallback mapping is intentionally empty pending direct Forever client verification. The installed Forever QuestieDB 1.0.6 dataset identifies Crown of the Earth as quest **921**, with source item **5185**, Crystal Phial. The local client cache did not contain that quest, so the pair is documented as a candidate, not enabled as a verified mapping. Native detection does not depend on this table or on Questie. To expand coverage, verify both IDs and the item's use action in the target client, then add `[questID] = {itemID, ...}` with a build/source comment in `QuestItems.lua`.

Item actions use `SecureActionButtonTemplate` (`type1="item"`, `item1="item:<ID>"`). The actual icon, count and cooldown belong to the animated row. A separate, texture-free secure click target mirrors its screen position and is never parented or anchored to the tracker. This keeps protected-frame restrictions from propagating to the animated rows. Hit targets are withheld for clipped/masked icons, cleared on inventory changes, and rebound by quest key and item ID before reuse. The mouse wheel also works over item icons.

**Combat limitation:** a `SecureHandlerStateTemplate` state driver hides the click targets during combat. Icons and normal tracker updates continue, with an explanatory tooltip; quest-item quick-use resumes after combat and a data refresh. Missing secure templates/state-driver support leaves an informational icon with no use action. No insecure click handler calls an item-use function, and no targeting or ground location is selected automatically.

Bag scans are cached and invalidated by bag, item-data and relevant quest events; there are no per-frame bag scans. Cooldowns use `C_Container.GetItemCooldown` / `GetItemCooldown`, container-slot cooldowns, or the quest special-item cooldown as available. Missing metadata waits for item-data events; absent cooldown APIs simply omit the overlay.

### Verification

Run `lua Tests/QuestItems.lua` and `lua Tests/Completion.lua` with Lua 5.1. These are mocked tests, including strict rejection of protected changes during simulated combat; they do **not** test Blizzard's secure execution engine or certify Forever runtime behavior.

In-game checklist:

- With a recognised item in your bags, check the actual icon and normal tooltip, then click once. Confirm the game's normal use/targeting cursor and that the parent quest does not receive the click.
- Check quests without usable items, two items on one quest, stack/charge counts, cooldowns, consumption and bag-slot moves.
- Collapse objectives, complete and reorder quests, remove a quest during its animation, and scroll across the viewport edges. Check that icons and click targets stay together.
- Resize, change UI scale, drag, minimize/hide/show, toggle the item setting and `/reload`; confirm layout and saved settings.
- Enter combat, change inventory/quests and collapse or scroll the tracker. Icons should explain that quick-use is unavailable; no blocked-action errors should appear. After combat, verify the correct actions return.
- For Crystal Phial, verify the live quest/item IDs and native special-item result before enabling its fallback mapping. Only then test filling it at the moonwell.

## Blizzard tracker suppression and quest navigation

The previous alpha-only hiding left Blizzard's child buttons interactive. `BlizzardUI.lua` now discovers all present `ObjectiveTrackerFrame`, `WatchFrame` and `QuestWatchFrame` roots and calls `Hide()`, removing their descendants from mouse hit testing. Local Forever compatibility code identifies `ObjectiveTrackerFrame` as the native root; the other names cover legacy clients. A tooltip already owned by a suppressed root or descendant is dismissed. Native events and quest-watch data remain untouched.

Each root's visibility, alpha and mouse-enabled state are saved. An `OnShow` hook re-hides native show attempts without accumulating hooks or forcing visibility every frame. Quest, zone, UI and addon-load events, plus the existing periodic refresh, discover late roots and retry pending changes. Disabling **Hide Blizzard quest tracker** restores saved state, including a native request to show a previously hidden root. Hooks become inert while disabled. Logout invokes cleanup; disabling/removing the addon through the game's addon manager takes effect on reload. There is no general live addon-unload API assumed here.

Forbidden frames are skipped. Protected roots cannot be hidden during combat; if Blizzard re-shows one, it can remain visible until combat ends. Unprotected roots can still be hidden safely. All restoration waits until combat ends, then applies the latest setting. These guards require verification against Forever's actual frame protection and native update behavior.

Title navigation resolves a stable quest ID at click time through `C_QuestLog.GetLogIndexForQuestID`, `GetQuestLogIndexByID`, or a fresh log scan, validating the returned entry. Legacy navigation uses `ShowUIPanel` (with `ToggleQuestLog`/`Show` fallbacks), `QuestLog_SetSelection` or `SelectQuestLogEntry`, and native detail updates. ID-based clients can use `C_QuestLog.SetSelectedQuest` or `QuestMapFrame_OpenToQuestDetails`. An already-open log stays open, and selection is resolved again after opening. Shift-click links are also checked against the current quest ID.

Missing quests or unsupported APIs produce a brief message. Without IDs, only a unique matching title/level at the unchanged stored index is accepted. Title navigation pauses while rows animate or are masked, then resumes using the row's current quest. Navigation is withheld during combat and Forever controller mode; open the native log manually in those cases. The controller guard follows the installed Forever compatibility code's warning about addon-driven quest-log opening.

### Verification

Run `lua Tests/BlizzardUI.lua`, `lua Tests/Completion.lua` and `lua Tests/QuestItems.lua` with Lua 5.1. The native UI suite covers all three roots, repeated toggles, descendant tooltips, native re-show attempts, replacement roots, forbidden/protected frames, cleanup, stale indices, both selection API families, wrapped titles and clicks during animation. These mock checks cannot certify actual mouse pass-through, taint safety or native quest details.

In-game checklist:

- Enable hiding and hover/click the original tracker area: no tracker, tooltip hotspots or hidden buttons; input reaches the world or visible UI. XenQuest remains interactive.
- Accept, progress, complete and abandon quests; change zones and UI settings, log in and `/reload`. Check continued suppression and native map/minimap tracking.
- Toggle hiding repeatedly; verify normal Blizzard rows, clicks and tooltips return. Toggle during combat, then leave combat and confirm the latest setting, with no Lua or blocked-action errors. Test disabling the addon followed by reload.
- Click incomplete and completed titles, including wrapped titles and after sorting. Confirm the exact quest's description, objectives and rewards. Repeat with the log already open and after accepting/abandoning another quest.
- Try title clicks during the completion animation and after settling. Check marker tracking/tooltips, item use/tooltips, right-click collapse and Shift-click sharing independently; child clicks must not open the log.
