-- XenQuest Objective Guidance, phase 1: exact-match text replacement
-- plus an opt-in, bounded recorder for quest IDs and objective labels.
-- Data never comes from guesses and no network calls are used at runtime.
local ADDON_NAME, addon = ...
local Guidance={}
addon.ObjectiveGuidance=Guidance
local db
local MAX_QUESTS,MAX_OBJECTIVES=500,24

local function cleanLabel(raw)
    if type(raw)~="string" then return "" end
    local s=raw:gsub("^%s*%d+%s*/%s*%d+%s*","")
    s=s:gsub("^%s*:%s*",""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$","")
    return s:match("^%s*(.-)%s*$") or ""
end
local function keyFor(raw)
    return cleanLabel(raw):lower():gsub("%s+"," ")
end
local function questKey(quest)
    local id=tonumber(quest.id)
    if id and id>0 then return "id:"..tostring(math.floor(id)) end
    local title=keyFor(quest.title)
    if title~="" then return "title:"..title end
end
function Guidance:Initialize(saved)
    db=saved
    if db.helpfulObjectives==nil then db.helpfulObjectives=true end
    if db.guidanceCaptureEnabled==nil then db.guidanceCaptureEnabled=false end
    if type(db.guidanceCapture)~="table" then db.guidanceCapture={} end
end
function Guidance:Describe(quest,original)
    if not db or db.helpfulObjectives==false or type(original)~="string" then return original end
    if addon.NativeLearning and type(addon.NativeLearning.Describe)=="function" then
        local native=addon.NativeLearning:Describe(quest,original)
        if type(native)=="string" and native~="" then return native end
    end
    -- This build uses native learning and independently verified manual corrections.
    local label=keyFor(original)
    if label=="" then return original end
    local data=addon.QuestGuidanceData
    if not data then return original end
    local id=quest and tonumber(quest.id)
    local title=quest and keyFor(quest.title)
    local record=id and data.questsByID and data.questsByID[id]
    -- A Forever-custom quest can reuse a normal Classic quest ID. Never
    -- apply a generated entry if its expected quest title differs.
    if record and record.title and keyFor(record.title)~=title then
        record=nil
    end
    -- Preserve the older, exact-title legacy hints when no quest-ID match.
    if not record then
        record=title and data.questsByTitle and data.questsByTitle[title]
    end
    local value=record and record.objectives and record.objectives[label]
    if type(value)=="string" and value~="" then return value end
    return original
end
function Guidance:Capture(quest)
    if not db or not db.guidanceCaptureEnabled or type(quest)~="table" then return end
    local key=questKey(quest)
    if not key then return end
    local store=db.guidanceCapture
    if type(store)~="table" then store={};db.guidanceCapture=store end
    local record=store[key]
    if not record then
        local n=0
        for _ in pairs(store) do n=n+1 end
        if n>=MAX_QUESTS then return end
        record={questID=tonumber(quest.id),title=tostring(quest.title or ""),
            zone=tostring(quest.zone or ""),objectives={}}
        store[key]=record
    end
    if type(record.objectives)~="table" then record.objectives={} end
    for _,o in ipairs(quest.objectives or {}) do
        local label=cleanLabel(o.text or o.description or o.objectiveText)
        if label~="" then
            local normalized=keyFor(label)
            local found=false
            for _,known in ipairs(record.objectives) do
                if keyFor(known.text)==normalized then found=true;break end
            end
            if not found and #record.objectives<MAX_OBJECTIVES then
                record.objectives[#record.objectives+1]={
                    text=label,kind=tostring(o.type or o.objectiveType or "")}
            end
        end
    end
end
function Guidance:GetCaptureCount()
    local n=0
    if db and type(db.guidanceCapture)=="table" then
        for _ in pairs(db.guidanceCapture) do n=n+1 end
    end
    return n
end
function Guidance:Status()
    print("|cffe8bb59XenQuest Guidance|r: descriptions "..(db.helpfulObjectives and "ON" or "OFF")..
        "; recording "..(db.guidanceCaptureEnabled and "ON" or "OFF")..
        "; "..self:GetCaptureCount().." quests recorded.")
end
function Guidance:HandleCommand(raw,inspect)
    if not db then return false end
    local command=(raw or ""):lower():match("^%s*(.-)%s*$")
    if command=="on" then db.helpfulObjectives=true;self:Status();return true end
    if command=="off" then db.helpfulObjectives=false;self:Status();return true end
    if command=="record on" then
        db.guidanceCaptureEnabled=true
        print("|cffe8bb59XenQuest Guidance|r: recording enabled. Use /xq guide record off to stop.")
        return true
    end
    if command=="record off" then
        db.guidanceCaptureEnabled=false
        print("|cffe8bb59XenQuest Guidance|r: recording stopped; saved records are retained.")
        return true
    end
    if command=="status" then self:Status();return true end
    if command=="inspect" then if inspect then inspect() end;return true end
    print("|cffe8bb59XenQuest Guidance|r: /xq guide on|off, /xq guide record on|off, /xq guide status, /xq guide inspect")
    return true
end
