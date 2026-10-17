# XenQuest Development Toolkit

This contains **tools only**. It deliberately does not include `Core.lua`, quest databases, or other addon files. Start by unpacking your **latest working complete XenQuest ZIP** into this project's `XenQuest/` subfolder.

Expected layout:

```text
Coding-Projects/
  XenQuest/                 <- PROJECT ROOT (open this in VS Code)
    XenQuest/               <- ACTUAL ADDON SOURCE (contents of release ZIP)
      XenQuest.toc
      Core.lua
      Navigation.lua
      Data/
      Media/
    Tools/                  <- PowerShell scripts
    Docs/                   <- release instructions
    Versions/               <- locally packaged ZIPs
    Backups/                <- backups of in-game install
    .gitignore
    01-Configure.cmd
    02-Install-to-WoW.cmd
    03-Package-Version.cmd
```

## Do this in order

1. Extract your latest **working** addon ZIP at the project root. Confirm the TOC is at `Coding-Projects\XenQuest\XenQuest\XenQuest.toc`. Avoid a third `XenQuest` folder.
2. Extract this toolkit at the same project root, merging directories.
3. Run **01-Configure.cmd** once, specifying the `Interface\AddOns` folder in your active WoW client.
4. Run **02-Install-to-WoW.cmd** whenever you want to test a code change, then type `/reload` in game.
5. When a version is ready, edit the version field in the TOC and run **03-Package-Version.cmd**. Your ZIP appears in `Versions/` with the proper installable `XenQuest/` root folder.

**Important:** `03-Package-Version.cmd` deliberately creates a `-LOCAL-TEST.zip`, not an upload-ready public release. Some v0.2.12 guidance data has unresolved redistribution rights. See `Docs/RELEASE_PROCESS.md` before publishing.

**Git:** preserve your `.git` history if it exists; otherwise clone your existing GitHub repository before changing its structure. `Versions/` is excluded from Git.
