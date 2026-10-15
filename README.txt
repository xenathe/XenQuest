XenQuest v0.2.3-beta - WoW Forever quest-tracker replacement
============================================================
Install the entire XenQuest folder under Interface/AddOns, then restart WoW.

/xq or /xenquest  Open settings
/xq all           Show all quests in the quest log
/xq tracked       Show only watched quests (default)
/xq reset         Reset tracker position
/xq show          Show XenQuest
/xq hide          Hide XenQuest

Features
- Incomplete quests first; Blizzard quest-log order is retained within each group.
- New completions shimmer green, collapse and glide below incomplete quests.
- Automatic collapse preserves saved choices; right-click still expands details.
- Optional quest-item icons with tooltips, counts, cooldowns and secure click-to-use.
  Enabled by default; quick-use is unavailable during combat. See README.md for
  detection coverage, verified-mapping requirements and the in-game test checklist.
- Quest levels, names, status symbols (!) and (?) in circular frames.
- Live per-objective counts and gold progress bars; complete bars turn green.
- Left-click a quest title to open that quest in Blizzard's quest log.
- Timed quests show a live countdown beside the title, including timed turn-ins.
- Right-click a quest row to expand/collapse objectives; markers control tracking.
- Shift-click quest title to link quest in chat where supported.
- Drag the XenQuest tracker; adjustable width, height, UI scale and font.
- Fully transparent background at 0% while bars and text remain visible.
- Settings: opacity, scale, width, height, font family, font size, accent theme,
  hide/show Blizzard tracker, watched-only display, lock position.

Compatibility and limitations
- This is a beta build and needs testing in WoW Forever (Interface 16001).
- XenQuest never auto-accepts, abandons or turns in quests.
- On clients exposing no watch-list API, watched-only mode falls back to all
  quest-log entries rather than displaying a blank tracker.
- Some custom quest objectives may not expose numerical progress; those remain
  plain text without a made-up bar.
- Blizzard tracker roots are hidden, including their child mouse regions, and
  restored when hiding is disabled. Native quest/map tracking remains enabled.
  Protected changes and restoration wait until combat ends; forbidden roots
  are skipped. See README.md for compatibility details and in-game checks.
- Title navigation pauses during movement and is unavailable during combat or
  Forever controller mode. Missing/ambiguous quests are never guessed.
- The tracker uses Blizzard's native font files; no font files are bundled.
- You can restore the original tracker by unchecking Hide Blizzard tracker.
- Do not remove your SavedVariables file when updating.
