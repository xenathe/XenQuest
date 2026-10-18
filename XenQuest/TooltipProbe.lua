-- XenQuest tooltip diagnostic v4 -- WoW Forever LOCAL TEST ONLY.
-- Read-only; never teaches quest mappings or modifies quest/tooltips.
-- No per-frame scanner and no TooltipDataProcessor callbacks.
local _, addon = ...
local Probe = {}
addon.TooltipProbe = Probe

local enabled = false
local last, recent = nil, {}
local errors, lastError, attempts = 0, nil, 0
local busy, pending = false, false
local hookLabel = "none"
local MAX_LINES, MAX_RECENT, MAX_CHARS = 24, 6, 170
local lineTypes = (Enum and Enum.TooltipDataLineType) or {}
local questTitle = lineTypes.QuestTitle or 17
local questObjective = lineTypes.QuestObjective or 8

-- Forever may return secret strings/numbers/booleans even when type() reports
-- an ordinary Lua type. Never pattern-match, compare or print them unchecked.
local function accessible(value)
    if type(canaccessvalue) == "function" then
        local ok, yes = pcall(canaccessvalue, value)
        return ok and yes == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == false
    end
    return true  -- Classic clients without the secret-value APIs.
end

local function read(fn, ...)
    if type(fn) ~= "function" then return nil, "API unavailable" end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, "API call failed" end
    if not accessible(value) then return nil, "restricted by client" end
    return value, nil
end

local function readPair(fn, ...)
    if type(fn) ~= "function" then return nil, nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or not accessible(a) or not accessible(b) then return nil, nil end
    return a, b
end

local function out(s)
    if type(print) == "function" then
        print("|cffe8bb59XenQuest Probe|r: "..tostring(s))
    end
end

local function clean(s)
    if not accessible(s) or type(s) ~= "string" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[\r\n\t]", " ")
    if #s > MAX_CHARS then s = s:sub(1, MAX_CHARS).."..." end
    return s
end

local function guidType(guid)
    if not accessible(guid) or type(guid) ~= "string" then return nil end
    return guid:match("^([A-Za-z]+)%-")
end

local function npcIDFromGuid(guid)
    local kind = guidType(guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
end

local function lineKind(t)
    if not accessible(t) then return "RESTRICTED" end
    if t == questTitle then return "QUEST TITLE" end
    if t == questObjective then return "QUEST OBJECTIVE" end
    return tostring(t or "?")
end

local function apiLines(unit)
    local fn = C_TooltipInfo and C_TooltipInfo.GetUnit
    if type(fn) ~= "function" then return {}, 0, "structured API unavailable" end
    local data, reason = read(fn, unit)
    if not data then return {}, 0, reason or "no structured tooltip" end
    if type(data) ~= "table" then return {}, 0, "structured response not a table" end
    local ok, lines = pcall(function() return data.lines end)
    if not ok or not accessible(lines) or type(lines) ~= "table" then
        return {}, 0, "structured lines unavailable"
    end
    local result, count = {}, 0
    for i=1,math.min(#lines, MAX_LINES) do
        local line = lines[i]
        if accessible(line) and type(line) == "table" then
            local okLine, left, right, kind = pcall(function()
                return line.leftText, line.rightText, line.type
            end)
            if okLine then
                local lhs, rhs = clean(left), clean(right)
                local label = lhs
                if rhs ~= "" then label = (label ~= "" and label.." | " or "")..rhs end
                if label ~= "" then
                    result[#result+1] = {kind=lineKind(kind), text=label}
                    if accessible(kind) and (kind == questTitle or kind == questObjective) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return result, count, (#result > 0 and "available" or "no readable structured lines")
end

local function visibleLines(tooltip, unit, guid, name)
    if not tooltip then return {}, "no GameTooltip" end
    local shown = read(tooltip.IsShown, tooltip)
    if shown == false then return {}, "GameTooltip hidden" end
    local tipName = read(tooltip.GetName, tooltip)
    if type(tipName) ~= "string" or tipName == "" then tipName = "GameTooltip" end
    local _, tipUnit = readPair(tooltip.GetUnit, tooltip)
    local matched, method = false, "not matched to this unit"
    if type(tipUnit) == "string" then
        local same = read(UnitIsUnit, unit, tipUnit)
        if same == true then matched, method = true, "same unit" end
        if not matched and guid then
            local otherGUID = read(UnitGUID, tipUnit)
            if otherGUID and guid == otherGUID then
                matched, method = true, "matching GUID"
            end
        end
    end
    -- Name-only matches are evidence for *diagnostics*, NOT trustworthy
    -- evidence for automatic quest/NPC learning (duplicate NPC names exist).
    if not matched and name and name ~= "" then
        local first = _G[tipName.."TextLeft1"]
        local tipHeader = clean(first and read(first.GetText, first))
        if tipHeader ~= "" and tipHeader == name then
            matched, method = true, "name-only (unverified)"
        end
    end
    if not matched then return {}, method end
    local n = read(tooltip.NumLines, tooltip)
    if type(n) ~= "number" or n < 1 then n = MAX_LINES end
    local result = {}
    for i=1,math.min(n, MAX_LINES) do
        local left = _G[tipName.."TextLeft"..i]
        local right = _G[tipName.."TextRight"..i]
        local lhs = clean(left and read(left.GetText, left))
        local rhs = clean(right and read(right.GetText, right))
        if rhs ~= "" then lhs = (lhs ~= "" and lhs.." | " or "")..rhs end
        if lhs ~= "" then result[#result+1] = lhs end
    end
    return result, method
end

local function hints(entry)
    if entry.nativeQuestCount > 0 then return true end
    for _,line in ipairs(entry.visible) do
        if line:match("%d+%s*/%s*%d+") then return true end
    end
    return false
end

local function scan(unit, origin, includeAPI)
    attempts = attempts + 1
    local exists, existsReason = read(UnitExists, unit)
    if exists == false then return nil, "No unit selected (UnitExists=false)." end
    local player = read(UnitIsPlayer, unit)
    if player == true then return nil, "Selected unit is a player, not an NPC." end
    local ownPet = read(UnitIsUnit, unit, "pet")
    if ownPet == true then return nil, "Selected unit is your pet." end
    local guid, guidReason = read(UnitGUID, unit)
    local kind = guidType(guid)
    if kind and kind ~= "Creature" and kind ~= "Vehicle" then
        return nil, "Unit GUID identifies a "..kind..", not a creature."
    end
    local name, nameReason = read(UnitName, unit)
    if type(name) ~= "string" or name == "" then name = nil end
    local id, idReason = read(UnitCreatureID, unit)
    if type(id) ~= "number" or id <= 0 then id = npcIDFromGuid(guid) end
    -- Even when the GUID is restricted or the tooltip is closed, this is still
    -- a valid target scan. Do not require tooltip lines just to store/report it.
    if not name and not id and exists ~= true then
        return nil, "No readable target identity ("..(existsReason or nameReason or "unknown")..")."
    end
    local native, count, apiStatus = {}, 0, "not requested"
    if includeAPI then native, count, apiStatus = apiLines(unit) end
    local visible, match = visibleLines(GameTooltip, unit, guid, name)
    local entry = {
        name = name or "<name restricted>", id = id, guid = guid,
        guidStatus = guid and "available" or (guidReason or "unavailable"),
        nameStatus = name and "available" or (nameReason or "unavailable"),
        idStatus = id and "available" or (idReason or "unavailable"),
        origin = origin, native = native, nativeQuestCount = count,
        visible = visible, match = match, apiStatus = apiStatus,
        exists = exists, verifiedNPC = (kind == "Creature" or kind == "Vehicle") or (id ~= nil),
    }
    -- Deduplicate only when we have a safe, concrete GUID.
    if guid then
        for i,v in ipairs(recent) do
            if v.guid and v.guid == guid then
                if #native == 0 and #v.native > 0 then
                    entry.native, entry.nativeQuestCount, entry.apiStatus = v.native, v.nativeQuestCount, v.apiStatus
                end
                if #visible == 0 and #v.visible > 0 then
                    entry.visible, entry.match = v.visible, v.match
                end
                table.remove(recent, i)
                break
            end
        end
    end
    entry.questHint = hints(entry)
    table.insert(recent, 1, entry)
    while #recent > MAX_RECENT do table.remove(recent) end
    last = entry
    return entry
end

local function guardedScan(unit, origin, includeAPI)
    if busy then return nil, "Probe busy." end
    busy = true
    local ok, entry, reason = pcall(scan, unit, origin, includeAPI)
    busy = false
    if not ok then
        errors = errors + 1
        lastError = tostring(entry)
        return nil, "Diagnostic scan failed. Run /xq probe status."
    end
    return entry, reason
end

local function captureTooltip(origin)
    if not enabled or not GameTooltip then return end
    local _, unit = readPair(GameTooltip.GetUnit, GameTooltip)
    if type(unit) ~= "string" or unit == "" then unit = "mouseover" end
    guardedScan(unit, origin, true)
end

local function delayedSample()
    if not enabled or pending or not C_Timer or type(C_Timer.After) ~= "function" then return end
    pending = true
    local ok = pcall(C_Timer.After, 0.25, function()
        pending = false
        if enabled then captureTooltip("deferred tooltip") end
    end)
    if not ok then pending = false end
end

local function printCapture(entry)
    if not entry then out("No NPC snapshot. Select a creature and run /xq probe target."); return end
    out("Target: "..clean(entry.name).." | NPC ID: "..tostring(entry.id or "unavailable")..
        (entry.verifiedNPC and " [ID verified]" or " [identity not fully verified]"))
    out("GUID: "..entry.guidStatus.."; name: "..entry.nameStatus.."; NPC ID: "..entry.idStatus)
    out("Source: "..entry.origin.."; structured API: "..entry.apiStatus..
        "; typed quest lines: "..entry.nativeQuestCount)
    out("Visible tooltip: "..#entry.visible.." lines; match: "..entry.match)
    for i,v in ipairs(entry.native) do out("API "..i.." ["..v.kind.."] "..v.text) end
    for i,v in ipairs(entry.visible) do out("UI "..i.." "..v) end
    if #entry.native == 0 and #entry.visible == 0 then
        out("NPC scan complete, but no quest tooltip lines were accessible. Hover the NPC, then run /xq probe last.")
    elseif entry.nativeQuestCount == 0 then
        out("Visible quest hints alone are not proof of native quest data or a drop relationship.")
    end
end

function Probe:HandleCommand(raw)
    local cmd = (raw or ""):lower():match("^%s*(.-)%s*$") or ""
    if cmd == "on" then
        enabled = true
        out("ON. Target an NPC with /xq probe target, or hover one and use /xq probe last.")
    elseif cmd == "off" then
        enabled = false
        out("OFF. Automatic tooltip capture disabled.")
    elseif cmd == "target" then
        enabled = true
        local entry, reason = guardedScan("target", "manual target", true)
        if entry then printCapture(entry)
        else out(reason or "Could not scan selected target.") end
    elseif cmd == "scan" then
        enabled = true
        local entry, reason = guardedScan("mouseover", "manual mouseover", true)
        if entry then printCapture(entry)
        else out(reason or "No mouseover NPC available.") end
    elseif cmd == "last" or cmd == "visible" then
        printCapture(last)
    elseif cmd == "recent" then
        if #recent == 0 then out("No NPC captures yet.") end
        for i,v in ipairs(recent) do
            out(i..". "..clean(v.name).." ("..tostring(v.id or "?")..")"..
                (v.questHint and " [quest hint]" or ""))
        end
    elseif cmd == "status" then
        out("Enabled="..tostring(enabled).."; hook="..hookLabel.."; attempts="..attempts..
            "; captured="..#recent.."; internal errors="..errors)
        if lastError then out("Last internal error: "..clean(lastError)) end
    elseif cmd == "clear" then
        recent, last = {}, nil
        out("Snapshots cleared.")
    else
        out("Commands: on | off | target | scan | last | visible | recent | status | clear")
    end
    return true
end

if GameTooltip and type(GameTooltip.HookScript) == "function" then
    local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function()
        if not enabled then return end
        captureTooltip("GameTooltip OnTooltipSetUnit")
        delayedSample()
    end)
    if ok then hookLabel = "GameTooltip OnTooltipSetUnit" end
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "UPDATE_MOUSEOVER_UNIT")
f:SetScript("OnEvent", function()
    if not enabled then return end
    guardedScan("mouseover", "UPDATE_MOUSEOVER_UNIT", true)
    delayedSample()
end)

SLASH_XQPROBE1 = "/xqprobe"
SlashCmdList.XQPROBE = function(raw) Probe:HandleCommand(raw) end
