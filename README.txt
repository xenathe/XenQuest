XenQuest v0.1.0-beta — WoW Forever quest-tracker replacement
============================================================
Install the entire XenQuest folder under Interface/AddOns, then restart WoW.

/xq or /xenquest  Open settings
/xq all           Show all quests in the quest log
/xq tracked       Show only watched quests (default)
/xq reset         Reset tracker position
/xq show          Show XenQuest
/xq hide          Hide XenQuest

Features
- Quest levels, names, status symbols (!) and (?) in circular frames.
- Live per-objective counts and gold progress bars; complete bars turn green.
- Click a quest to give it a subtle highlight; right-click to collapse its objectives.
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
- Blizzard's quest tracking frame is made transparent, not deleted. If another
  addon skins/replaces the Blizzard tracker, disable XenQuest's Hide Blizzard
  tracker setting to avoid conflicts.
- The tracker uses Blizzard's native font files; no font files are bundled.
- You can restore the original tracker by unchecking Hide Blizzard tracker.
- Do not remove your SavedVariables file when updating.
