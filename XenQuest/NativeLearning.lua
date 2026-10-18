-- XenQuest Native Learning (WoW Forever beta native discovery)
-- Learns only exact active-quest / unfinished-objective relationships from
-- C_TooltipInfo native typed quest lines. Does NOT scrape other addons or use
-- imported QuestieDB files, auto-target, or perform game actions.
local _, addon = ...
local Learn = {}
addon.NativeLearning = Learn

local MAX_QUESTS, MAX_OBJECTIVES, MAX_NPCS = 750, 16, 12
local db
local captureCount = 0
local lastEvent = "not scanned"
local questTitleType = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17
local questObjectiveType = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8

local function accessible(value)
    if type(canaccessvalue) == "function" then
        local ok, yes = pcall(canaccessvalue, value)
        return ok and yes == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == false
    end
    return true
end
local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and accessible(value) then return value end
end
local function field(tbl, key)
    if not accessible(tbl) or type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if ok and accessible(value) then return value end
end
local function safeString(s)
    if not accessible(s) or type(s) ~= "string" then return nil end
    if #s > 240 then return nil end
    return s
end
local function clean(s)
    s = safeString(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    s = s:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    return s:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end
local function key(s) return clean(s):lower() end
local function count(tbl)
    local n=0
    for _ in pairs(tbl) do n=n+1 end
    return n
end
local function say(msg)
    if type(print)=="function" then print("|cffe8bb59XenQuest Learn|r: "..msg) end
end
local function getStore()
    if not db then return end
    if type(db.nativeLearning)~="table" then db.nativeLearning={version=1, quests={}} end
    if type(db.nativeLearning.quests)~="table" then db.nativeLearning.quests={} end
    return db.nativeLearning.quests
end
function Learn:Initialize(saved)
    db=saved
    if db.nativeLearningEnabled==nil then db.nativeLearningEnabled=false end
    db.nativeDataOnly=true -- This distribution never loads third-party generated quest datasets.
    getStore()
end
local function questRows()
    local rows={}
    local n=read(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or read(GetNumQuestLogEntries) or 0
    if type(n)~="number" then return rows end
    for i=1,math.min(n,500) do
        local id, title, header, complete
        if C_QuestLog and type(C_QuestLog.GetInfo)=="function" then
            local info=read(C_QuestLog.GetInfo,i)
            id=field(info,"questID")
            title=field(info,"title") or field(info,"name")
            header=field(info,"isHeader")
            complete=field(info,"isComplete")
        elseif type(GetQuestLogTitle)=="function" then
            local ok,a,_,_,d,_,f,_,h=pcall(GetQuestLogTitle,i)
            if ok and accessible(a) and accessible(d) and accessible(f) and accessible(h) then
                id,title,header,complete=h,a,d,f
            end
        end
        if type(id)=="number" and id>0 and safeString(title)
            and header~=true and complete~=true and complete~=1 then
            local objectives=read(C_QuestLog and C_QuestLog.GetQuestObjectives,id)
            if type(objectives)~="table" then
                objectives={}
                local nObj=read(GetNumQuestLeaderBoards,i)
                if type(nObj)=="number" then
                    for j=1,math.min(nObj,24) do
                        if type(GetQuestLogLeaderBoard)=="function" then
                            local ok,txt,kind,done=pcall(GetQuestLogLeaderBoard,j,i)
                            if ok and safeString(txt) then
                                objectives[#objectives+1]={text=txt,type=kind,finished=done}
                            end
                        end
                    end
                end
            end
            local labels={}
            for _,obj in ipairs(objectives) do
                local raw=field(obj,"text") or field(obj,"description") or field(obj,"objectiveText")
                local label=key(raw)
                local done=field(obj,"finished") or field(obj,"isFinished") or field(obj,"isComplete")
                if done~=true and label~="" then
                    -- Progress can also arrive embedded in a legacy text string.
                    local s=safeString(raw)
                    local have,need=s and s:match("(%d+)%s*/%s*(%d+)")
                    if not (have and need and tonumber(need)>0 and tonumber(have)>=tonumber(need)) then
                        labels[label]=clean(raw)
                    end
                end
            end
            rows[key(title)]={id=id,title=title,objectives=labels}
        end
    end
    return rows
end
local function npcIdentity(unit)
    if read(UnitIsPlayer,unit)==true or read(UnitIsUnit,unit,"pet")==true then return end
    if read(UnitExists,unit)==false or read(UnitIsDeadOrGhost,unit)==true then return end
    local name=safeString(read(UnitName,unit))
    local id=read(UnitCreatureID,unit)
    if type(id)~="number" or id<1 then
        local guid=read(UnitGUID,unit)
        if safeString(guid) then
            local kind=guid:match("^([%a]+)%-")
            if kind~="Creature" and kind~="Vehicle" then return end
            id=tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
        end
    end
    if type(id)~="number" or id<1 or id~=math.floor(id) or not name or name=="" then return end
    return id,name
end
local function tooltipQuests(unit)
    local data=read(C_TooltipInfo and C_TooltipInfo.GetUnit,unit)
    local lines=field(data,"lines")
    if type(lines)~="table" then return {} end
    local result,current={},nil
    for i=1,math.min(#lines,48) do
        local line=lines[i]
        local kind=field(line,"type")
        local text=field(line,"leftText")
        if safeString(text) then
            if kind==questTitleType then
                current=key(text)
            elseif kind==questObjectiveType and current and current~="" then
                result[#result+1]={quest=current,objective=key(text)}
            end
        end
    end
    return result
end
local function recordNPC(quest,objective, id, name)
    local store=getStore()
    if not store then return false end
    local record=store[quest.id]
    if record and key(record.title)~=key(quest.title) then return false end
    if not record then
        if count(store)>=MAX_QUESTS then return false end
        record={title=quest.title, objectives={}}
        store[quest.id]=record
    end
    local obj=record.objectives[objective]
    if not obj then
        if count(record.objectives)>=MAX_OBJECTIVES then return false end
        obj={label=quest.objectives[objective],npcs={}}
        record.objectives[objective]=obj
    end
    if not obj.npcs[id] then
        if count(obj.npcs)>=MAX_NPCS then return false end
        obj.npcs[id]=name
        return true
    end
    return false
end
function Learn:Scan(unit)
    if not db or not db.nativeLearningEnabled then return end
    local npcID,name=npcIdentity(unit)
    if not npcID then lastEvent="NPC identity unavailable or restricted"; return end
    local matches=tooltipQuests(unit)
    if #matches==0 then lastEvent="no typed quest lines for "..name; return end
    local active=questRows()
    local added=0
    for _,match in ipairs(matches) do
        local quest=active[match.quest]
        if quest and quest.objectives[match.objective] then
            if recordNPC(quest,match.objective,npcID,name) then added=added+1 end
        end
    end
    lastEvent=name.." ("..npcID..") - "..added.." new relation(s)"
    if added>0 then
        captureCount=captureCount+added
        say("Learned "..name.." for "..added.." active quest objective(s).")
        if addon.TargetMarkers and type(addon.TargetMarkers.Refresh)=="function" then
            pcall(addon.TargetMarkers.Refresh,addon.TargetMarkers)
        end
    end
end
function Learn:GetNPCs(id,title,label)
    if not db or not db.nativeLearningEnabled then return end
    local quests=getStore()
    local record=quests and quests[tonumber(id)]
    if not record or key(record.title)~=key(title) then return end
    local objective=record.objectives and record.objectives[key(label)]
    return objective and objective.npcs or nil
end
function Learn:Describe(quest,original)
    if not db or not db.nativeLearningEnabled or type(quest)~="table" then return end
    local npcs=self:GetNPCs(quest.id,quest.title,original)
    if not npcs then return end
    local npc
    local n=0
    for _,name in pairs(npcs) do n=n+1; npc=name end
    if n~=1 or not npc then return end -- Don't invent which NPC is preferable.
    local label=clean(original)
    if label=="" then return end
    local labelLower=label:lower()
    if labelLower:find("slain",1,true) or labelLower:find("killed",1,true) or labelLower:find("defeated",1,true) then
        return "Kill "..npc
    end
    -- A tooltip association does not prove that an item DROPS from a mob.
    -- Name the confirmed association without claiming an unverified loot source.
    return npc.." — "..label
end
function Learn:HandleCommand(raw)
    if not db then say("Addon not initialised yet."); return true end
    local cmd=(raw or ""):lower():match("^%s*(.-)%s*$") or ""
    if cmd=="on" then
        db.nativeLearningEnabled=true
        db.nativeDataOnly=true -- Exclude QuestieDB-derived maps when evaluating the test.
        say("ON, native-only mode. Visit a quest NPC and hover or target it.")
    elseif cmd=="off" then
        db.nativeLearningEnabled=false
        db.nativeDataOnly=true
        say("OFF; native learning paused (no imported guidance is included).")
    elseif cmd=="target" or cmd=="scan" then
        if not db.nativeLearningEnabled then
            say("Learning is OFF. Use /xq learn on first.")
        else
            local ok,err=pcall(self.Scan,self,cmd=="target" and "target" or "mouseover")
            if not ok then lastEvent="scan failed safely"; say("Scan failed; no data was saved.") end
            say("Last scan: "..lastEvent)
        end
    elseif cmd=="clear confirm" then
        db.nativeLearning={version=1,quests={}}
        say("Saved native discoveries deleted.")
    elseif cmd=="clear" then
        say("To delete saved discoveries, use /xq learn clear confirm")
    elseif cmd=="status" or cmd=="" then
        local store=getStore()
        say("Learning "..(db.nativeLearningEnabled and "ON" or "OFF")..
            "; native-only "..(db.nativeDataOnly and "ON" or "OFF")..
            "; quests saved "..count(store).."; this session "..captureCount.." relation(s).")
        say("Last scan: "..lastEvent)
    else
        say("Commands: /xq learn on | off | target | scan | status | clear confirm")
    end
    if addon.TargetMarkers and type(addon.TargetMarkers.Refresh)=="function" then
        pcall(addon.TargetMarkers.Refresh,addon.TargetMarkers)
    end
    return true
end

local listener=CreateFrame("Frame")
for _,event in ipairs({"UPDATE_MOUSEOVER_UNIT","PLAYER_TARGET_CHANGED"}) do
    pcall(listener.RegisterEvent,listener,event)
end
local function scanLater(unit)
    if not db or not db.nativeLearningEnabled then return end
    if C_Timer and type(C_Timer.After)=="function" then
        local original=read(UnitGUID,unit)
        if not original or not accessible(original) then return end
        pcall(C_Timer.After,0.18,function()
            local newer=read(UnitGUID,unit)
            -- Prevent delayed unit-token reuse from teaching the wrong mob.
            if newer and accessible(newer) and original==newer then
                pcall(Learn.Scan,Learn,unit)
            elseif not original or not newer then
                -- Don't trust an identity we cannot associate with the event.
                return
            end
        end)
    else
        pcall(Learn.Scan,Learn,unit)
    end
end
listener:SetScript("OnEvent",function(_,event)
    scanLater(event=="PLAYER_TARGET_CHANGED" and "target" or "mouseover")
end)
