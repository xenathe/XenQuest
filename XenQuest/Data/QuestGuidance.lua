-- XenQuest Objective Guidance data (Phase 1, Northshire live test).
-- Quest-specific instructions require confirmed quest IDs/objective labels.
-- Legacy Zenn's Bidding hints remain separated below, pending verification.
-- No changes are needed to Core.lua when adding verified guidance records.
local ADDON_NAME, addon = ...
addon.QuestGuidanceData = {
    formatVersion=1,
    questsByID={
        -- Northshire Valley: quest IDs and raw labels captured in-game
        -- on WoW Forever (Human Warlock, 2026-10-16).
        [7]={
            title="Kobold Camp Cleanup",
            objectives={
                ["kobold vermin slain"]="Kill Kobold Vermin",
            },
        },
        [33]={
            title="Wolves Across the Border",
            objectives={
                -- A Timber Wolf was shown in-game as associated with this
                -- quest and its Tough Wolf Meat objective. Do not infer
                -- unrelated creature/item sources from this record.
                ["tough wolf meat"]="Kill Timber Wolves to collect Tough Wolf Meat",
            },
        },
        [91741]={
            title="Nibbled-On Book",
            objectives={
                -- Quest already provides an actionable NPC name, so keep
                -- the instruction factual without adding an unverified map location.
                ["return the book to brother paxton"]="Return the book to Brother Paxton",
            },
        },
        -- Confirmed on Forever: a ground pickup near the Defias camp;
        -- NOT the "Stolen Books" object suggested by raw QuestieDB.
        [1598]={
            title="The Stolen Tome",
            objectives={
                ["powers of the void"]="Pick up Powers of the Void near the Defias camp",
            },
        },
        -- Confirmed on Forever: a custom quest, item from Kobold Workers.
        [91743]={
            title="Rascally Rodents",
            objectives={
                ["stolen book"]="Kill Kobold Workers to collect Stolen Books",
            },
        },
    },
    questsByTitle={
        ["zenn's bidding"]={
            -- These three phrases were moved verbatim from XenQuest v0.2.11.
            -- They are not new, independently verified data.
            objectives={
                ["nightsaber fang"]="Kill Nightsabers to collect Nightsaber Fangs",
                ["strigid owl feather"]="Kill Strigid Owls to collect Strigid Owl Feathers",
                ["webwood spider silk"]="Kill Webwood Spiders to collect Webwood Spider Silk",
            },
        },
    },
}
