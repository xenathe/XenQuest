-- XenQuest quest target swords (WoW Forever local test).
-- A cosmetic overlay; never sets raid markers, targets enemies or performs actions.
-- Only displays when a LIVE incomplete objective matches quest ID + title + label.
local _, addon = ...
local Markers = {}
addon.TargetMarkers = Markers

local controller = CreateFrame("Frame")
local plates = {}       -- [nameplate unit token] = nameplate frame
local overlays = setmetatable({}, {__mode="k"})
local wantedIDs = {}    -- currently needed NPC IDs
local wantedNames = {}  -- conservative fallback when NPC ID isn't exposed
local questCount, objectiveCount = 0, 0
local lastError
local usingDistance = false
local lastFallback = false

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

-- Forever (1.60.1) may return secret unit identity values, particularly in
-- dungeons/combat. These retain their Lua type but cannot be compared,
-- indexed, converted, or pattern-matched by tainted addon code.
-- A secret identity is not evidence for a quest target: skip it safely.
local function accessible(value)
    if type(canaccessvalue)=="function" then
        local ok, permitted=pcall(canaccessvalue,value)
        return ok and permitted==true
    end
    if type(issecretvalue)=="function" then
        local ok, secret=pcall(issecretvalue,value)
        return ok and secret==false
    end
    -- Compatibility with older clients that don't implement secret values.
    return true
end

local function log(text)
    if type(print)=="function" then print("|cffe8bb59XenQuest Targets|r: " .. text) end
end

local function enabled()
    return not XenQuestDB or XenQuestDB.questTargetMarkers ~= false
end

local function mode()
    return XenQuestDB and XenQuestDB.questTargetMarkerMode == "all" and "all" or "nearest"
end

local function markerSize()
    local size=tonumber(XenQuestDB and XenQuestDB.questTargetMarkerSize) or 32
    if size~=size then size=32 end -- NaN protection for corrupted saved settings
    return math.max(18,math.min(52,math.floor(size+0.5)))
end

local function resizeOverlay(overlay)
    if not overlay then return end
    local width=markerSize()
    if overlay.xqSwordWidth==width then return end
    -- Existing nameplates can be protected in combat on Forever. If resizing
    -- is disallowed, the refresh after combat will apply the pending size.
    if type(InCombatLockdown)=="function" and call(InCombatLockdown) then return end
    -- The approved sword artwork is taller than it is wide.
    local ok=pcall(overlay.SetSize,overlay,width,math.floor(width*38/32+0.5))
    if ok then overlay.xqSwordWidth=width end
end

local function normalize(value)
    if not accessible(value) or type(value) ~= "string" then return "" end
    local s = value:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    s = s:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    s = s:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    return s
end

local function isFinished(objective)
    local ok, done = pcall(function()
        if objective.finished == true or objective.isFinished == true or objective.isComplete == true then return true end
        local have = tonumber(objective.numFulfilled or objective.numCollected)
        local need = tonumber(objective.numRequired or objective.required)
        if need and need > 0 and have and have >= need then return true end
        local text = objective.text or objective.description
        if type(text) == "string" then
            local a, b = text:match("(%d+)%s*/%s*(%d+)")
            a, b = tonumber(a), tonumber(b)
            if b and b > 0 and a and a >= b then return true end
        end
        return false
    end)
    return ok and done == true
end

local function questLogInfo(i)
    if C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
        local v = call(C_QuestLog.GetInfo, i)
        if type(v)=="table" then
            local ok, id, header, complete, title = pcall(function()
                return tonumber(v.questID), v.isHeader, v.isComplete, v.title
            end)
            if ok and id then return id, header, complete, title end
        end
    end
    if type(GetQuestLogTitle)=="function" then
        local ok, title, _, _, header, _, complete, _, id = pcall(GetQuestLogTitle, i)
        if ok then return tonumber(id), header, complete, title end
    end
    return nil
end

local function numberOfEntries()
    local n = C_QuestLog and call(C_QuestLog.GetNumQuestLogEntries)
    if type(n)~="number" then n=call(GetNumQuestLogEntries) end
    return type(n)=="number" and n or 0
end

local function activeObjectives(id, index)
    local obj = C_QuestLog and call(C_QuestLog.GetQuestObjectives, id)
    if type(obj)=="table" and #obj>0 then return obj end
    local n = call(GetNumQuestLeaderBoards, index)
    if type(n)~="number" or n<=0 then return {} end
    local result = {}
    for j=1,n do
        if type(GetQuestLogLeaderBoard)=="function" then
            local ok, text, kind, done = pcall(GetQuestLogLeaderBoard,j,index)
            if ok and type(text)=="string" then
                result[#result+1] = {text=text, type=kind, finished=done}
            end
        end
    end
    return result
end

local function refreshObjectives()
    local data = addon.TargetMarkerData
    local records = data and data.quests
    local native = addon.NativeLearning
    local legacyAllowed = not (XenQuestDB and XenQuestDB.nativeDataOnly==true)
    wantedIDs, wantedNames = {}, {}
    questCount, objectiveCount = 0, 0
    if not enabled() then return end

    for index=1,numberOfEntries() do
        local id, header, complete, title = questLogInfo(index)
        if id and not header and not (complete==1 or complete==true) then
            local entry = legacyAllowed and type(records)=="table" and records[id] or nil
            if entry and normalize(entry.title)~=normalize(title) then entry=nil end
            local any = false
            for _,objective in ipairs(activeObjectives(id,index)) do
                local ok,label=pcall(function()
                    return normalize(objective.text or objective.description or objective.objectiveText)
                end)
                if ok and label~="" and not isFinished(objective) then
                    local learned = native and type(native.GetNPCs)=="function"
                        and native:GetNPCs(id,title,label)
                    local legacy = entry and entry.objectives and entry.objectives[label]
                    local matched=false
                    if type(learned)=="table" then
                        for npc,name in pairs(learned) do
                            if type(npc)=="number" and type(name)=="string" and name~="" then
                                wantedIDs[npc]=true
                                wantedNames[normalize(name)]=true
                                matched,any=true,true
                            end
                        end
                    end
                    if type(legacy)=="table" then
                        for _,npc in ipairs(legacy) do
                            if type(npc)=="number" then wantedIDs[npc]=true; matched,any=true,true end
                        end
                    end
                    if matched then objectiveCount=objectiveCount+1 end
                end
            end
            if any then questCount=questCount+1 end
        end
    end
    if legacyAllowed and data and type(data.npcs)=="table" then
        for npc in pairs(wantedIDs) do
            local name=data.npcs[npc]
            if type(name)=="string" and name~="" then wantedNames[normalize(name)]=true end
        end
    end
end

local function npcIDFromGuid(guid)
    -- type(secretGUID)=="string" is true even though :match() is forbidden.
    if not accessible(guid) or type(guid)~="string" then return nil end
    if guid:match("^Creature%-") or guid:match("^Vehicle%-") then
        return tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
    end
    -- Older clients or restricted identities may not expose a parseable GUID.
    return nil
end

local function unitIsRequired(unit)
    if not accessible(unit) then return false end
    local isPlayer=call(UnitIsPlayer,unit)
    if not accessible(isPlayer) then return false end
    if isPlayer==true then return false end
    local isDead=call(UnitIsDeadOrGhost,unit)
    if not accessible(isDead) then return false end
    if isDead==true then return false end
    if type(UnitCanAttack)=="function" then
        local attackable=call(UnitCanAttack,"player",unit)
        if not accessible(attackable) then return false end
        if attackable==false then return false end
    end
    local id=call(UnitCreatureID,unit)
    if not accessible(id) then id=nil end
    if type(id)~="number" or id<=0 then id=npcIDFromGuid(call(UnitGUID,unit)) end
    if type(id)=="number" and id>0 then return wantedIDs[id]==true end
    local name=call(UnitName,unit)
    -- Only use an accessible NPC name when there is no usable ID.
    if not accessible(name) then return false end
    return wantedNames[normalize(name)] == true
end

local function makeOverlay(plate)
    if type(InCombatLockdown)=="function" and call(InCombatLockdown) then return nil end
    local ok, frame = pcall(function()
        local marker=CreateFrame("Frame",nil,plate)
        resizeOverlay(marker)
        marker:SetPoint("BOTTOM",plate,"TOP",0,1)
        if type(marker.SetFrameLevel)=="function" and type(plate.GetFrameLevel)=="function" then
            marker:SetFrameLevel(plate:GetFrameLevel()+5)
        end
        local texture=marker:CreateTexture(nil,"OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\AddOns\\XenQuest\\Media\\QuestTargetSword")
        texture:SetTexCoord(0,1,0,1)
        texture:SetVertexColor(1,1,1,1)
        if type(marker.EnableMouse)=="function" then marker:EnableMouse(false) end
        marker:Hide()
        return marker
    end)
    if ok then return frame end
    lastError=tostring(frame)
    return nil
end

local function plateFor(unit)
    if not C_NamePlate then return nil end
    return call(C_NamePlate.GetNamePlateForUnit,unit)
end

local function refreshPlates()
    local candidates={}
    for unit,plate in pairs(plates) do
        if plate and enabled() and unitIsRequired(unit) then
            candidates[#candidates+1]={unit=unit,plate=plate}
        end
    end
    usingDistance, lastFallback = false,false
    local chosen
    if mode()=="nearest" and #candidates>1 then
        local closest, distance, valid = nil,nil,true
        for _,candidate in ipairs(candidates) do
            local squared, checked = call(UnitDistanceSquared,candidate.unit)
            if not accessible(squared) or not accessible(checked)
                or type(squared)~="number" or checked~=true or squared<0 then
                valid=false;break
            end
            if not distance or squared<distance then
                distance=squared;closest=candidate.plate
            end
        end
        if valid then
            chosen=closest
            usingDistance=true
        else
            -- WoW usually doesn't expose enemy distances. Never choose a
            -- pretend 'nearest' based on screen position or an arbitrary order.
            lastFallback=true
        end
    end
    local visible = {}
    for _,candidate in ipairs(candidates) do
        if (mode()=="all" or not chosen or candidate.plate==chosen) then
            visible[candidate.plate]=true
        end
    end
    for _,plate in pairs(plates) do
        local overlay=overlays[plate]
        if visible[plate] then
            if not overlay then
                overlay=makeOverlay(plate)
                if overlay then overlays[plate]=overlay end
            end
            if overlay then
                resizeOverlay(overlay) -- Update existing markers immediately when the size changes.
                overlay:Show()
            end
        elseif overlay then
            overlay:Hide()
        end
    end
end

local function discoverPlates()
    local all = C_NamePlate and call(C_NamePlate.GetNamePlates)
    if type(all)~="table" then return end
    for _,plate in ipairs(all) do
        local ok, unit = pcall(function() return plate.namePlateUnitToken or plate.unitToken end)
        if ok and accessible(unit) and type(unit)=="string" then plates[unit]=plate end
    end
end

function Markers:Refresh()
    refreshObjectives()
    discoverPlates()
    refreshPlates()
end

function Markers:ApplyMarkerSize()
    -- Changing the size is cosmetic and needs no new quest-log lookup.
    for _,overlay in pairs(overlays) do resizeOverlay(overlay) end
end

local function status()
    local visible, marked = 0,0
    for _,plate in pairs(plates) do
        visible=visible+1
        local overlay=overlays[plate]
        if overlay and overlay:IsShown() then marked=marked+1 end
    end
    local source = (XenQuestDB and XenQuestDB.nativeDataOnly) and "native-only"
        or (addon.TargetMarkerData and "native + legacy" or "native (no legacy)")
    log((enabled() and "ON" or "OFF")..", mode "..mode()..", data "..source..
        ", active quests "..questCount..", objectives "..objectiveCount..
        ", visible plates "..visible..", marked "..marked..".")
    if mode()=="nearest" and lastFallback then
        log("WoW does not expose exact enemy distance; showing all nearby matching nameplates instead.")
    end
    if lastError then log("Overlay error: "..lastError) end
end

SLASH_XQTARGETMARKERS1 = "/xqmarkers"
SlashCmdList.XQTARGETMARKERS=function(input)
    local cmd=normalize(input)
    XenQuestDB=XenQuestDB or {}
    if cmd=="on" or cmd=="off" then
        XenQuestDB.questTargetMarkers=(cmd=="on")
    elseif cmd=="all" or cmd=="nearest" then
        XenQuestDB.questTargetMarkerMode=cmd
        XenQuestDB.questTargetMarkers=true
    elseif cmd~="" and cmd~="status" then
        log("Use /xqmarkers on | off | nearest | all | status")
        return
    end
    Markers:Refresh()
    if type(addon.RefreshTargetMarkerSettingsUI)=="function" then
        addon.RefreshTargetMarkerSettingsUI()
    end
    status()
end

controller:RegisterEvent("NAME_PLATE_UNIT_ADDED")
controller:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
controller:RegisterEvent("QUEST_LOG_UPDATE")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:RegisterEvent("PLAYER_REGEN_ENABLED")
controller:RegisterEvent("PLAYER_TARGET_CHANGED")
controller:SetScript("OnEvent",function(_,event,unit)
    if event=="NAME_PLATE_UNIT_REMOVED" then
        if not accessible(unit) then return end
        local plate=plates[unit]
        if plate and overlays[plate] then overlays[plate]:Hide() end
        plates[unit]=nil
        refreshPlates()
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        if accessible(unit) and type(unit)=="string" then
            local plate=plateFor(unit)
            if plate then plates[unit]=plate end
        end
        refreshPlates()
    elseif event=="PLAYER_TARGET_CHANGED" or event=="PLAYER_REGEN_ENABLED" then
        refreshPlates()
    else
        Markers:Refresh()
    end
end)

-- Nearest selection must respond to movement, and some Forever objective
-- updates arrive without QUEST_LOG_UPDATE. Small bounded check, no networking.
local elapsed=0
controller:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+(dt or 0)
    if elapsed>=1.25 then
        elapsed=0
        if enabled() then Markers:Refresh() end
    end
end)
