-- XenQuest 0.2.5-beta. Standalone quest tracker for WoW Forever / Classic-era clients.
-- Never changes the quest log or uses protected quest actions automatically.
local ADDON_NAME,addon = ...
local QuestItems,ItemButtons=addon.QuestItems,addon.QuestItemButtons
local BlizzardUI=addon.BlizzardUI
local XQ = CreateFrame("Frame")
local db, tracker, settings, rows = nil, nil, nil, {}
local dirty, elapsed = true, 0
local renderedQuestIDs = {}
-- Session-only state: saved manual collapse choices are never changed by completion.
local questStates, spareRows, paintOrder = {}, {}, {}
local completionSerial, layoutHeight = 0, 1
local completionBaseline, worldReady = true, false
local layoutRows, finishAnimations
local SHIMMER_END, GLIDE_START, GLIDE_END, ANIMATION_END = 0.22, 0.40, 1.02, 1.26

local COLORS = {
    background={0.035,0.072,0.10}, surface={0.10,0.17,0.21}, edge={0.20,0.31,0.37},
    gold={0.96,0.77,0.36}, green={0.42,0.84,0.58}, white={0.94,0.96,0.97},
    muted={0.65,0.73,0.76}, barbg={0.16,0.23,0.27}, blue={0.45,0.75,0.91},
}
local FONTS = {
    {label="Friz Quadrata", path="Fonts\\FRIZQT__.TTF"},
    {label="Arial Narrow", path="Fonts\\ARIALN.TTF"},
    {label="Morpheus", path="Fonts\\MORPHEUS.TTF"},
    {label="Skurri", path="Fonts\\SKURRI.TTF"},
    {label="Custom", path="Interface\\AddOns\\XenQuest\\Media\\custom.ttf"},
}
local DEFAULTS = {
    x=-36,y=-175,scale=1,width=325,height=430,opacity=0,font=1,fontSize=12,
    trackedOnly=true,hideBlizzard=true,showHeader=true,locked=false,compact=false,
    theme="gold", primaryQuest=0, collapsed={}, minimized=false,showQuestItems=true,
}
local function safe(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d,e,f,g,h=pcall(fn,...)
    if ok then return a,b,c,d,e,f,g,h end
end
local function color(tex,c,alpha)
    tex:SetColorTexture(c[1],c[2],c[3],alpha == nil and 1 or alpha)
end
local function solid(parent,layer,rgba)
    local t=parent:CreateTexture(nil,layer or "BACKGROUND")
    t:SetAllPoints(parent)
    color(t,rgba)
    return t
end
local function fontString(parent,size,col,justify)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetJustifyH(justify or "LEFT")
    f:SetJustifyV("TOP")
    f:SetShadowColor(0,0,0,0.65)
    f:SetShadowOffset(1,-1)
    f.xqSize=size or 12
    f.xqColor=col or COLORS.white
    return f
end
-- Check the actual font resource, not merely the selected dropdown option.
local customFontProbe
local function customFontAvailable()
    if not customFontProbe then customFontProbe=CreateFont("XenQuestCustomFontProbe") end
    local font=customFontProbe
    if not font then return false end
    local ok,loaded=pcall(font.SetFont,font,FONTS[#FONTS].path,14,"")
    return ok and loaded~=false
end
local function fontChoiceLabel()
    local choice=FONTS[db.font] or FONTS[1]
    if db.font==#FONTS then
        return customFontAvailable() and "Custom (loaded)" or "Custom (NOT FOUND)"
    end
    return choice.label
end
local function applyFont(f,size,flags)
    if not f then return end
    local chosen=FONTS[db.font] or FONTS[1]
    local actualSize=math.max(9,(size or f.xqSize or 12)+(db.fontSize-12))
    local ok,loaded=pcall(f.SetFont,f,chosen.path,actualSize,flags or "")
    if not ok or loaded==false then safe(f.SetFont,f,"Fonts\\FRIZQT__.TTF",actualSize,flags or "") end
    local c=f.xqColor or COLORS.white
    f:SetTextColor(c[1],c[2],c[3])
end
local function backing(parent,base)
    local tex=solid(parent,"BACKGROUND",base or COLORS.background)
    return tex
end
local function setText(fs,str,width)
    fs:SetText(str or "")
    if width then fs:SetWidth(math.max(24,width)) end
end
local function formatStatus(o)
    local count=tonumber(o.numFulfilled or o.numCompleted or o.current or o.fulfilled)
    local total=tonumber(o.numRequired or o.required or o.total)
    local raw=tostring(o.text or o.description or o.objectiveText or "")
    if not count or not total then
        local a,b=raw:match("(%d+)%s*/%s*(%d+)")
        if a and b then count,total=tonumber(a),tonumber(b) end
    end
    -- Remove the leading numerical counter from default Blizzard objective text.
    local description=raw:gsub("^%s*%d+%s*/%s*%d+%s*","")
    description=description:gsub("^%s*:%s*","")
    if description=="" then description=raw end
    if description=="" then description="Objective" end
    local complete=o.finished==true or o.isFinished==true or o.isComplete==true
    if count and total and total>0 and count>=total then complete=true end
    return description,count,total,complete
end
-- Deliberately small, verified guidance map. Unknown objectives keep the game text;
-- guessing enemy/drop associations would be misleading. More entries can be
-- added safely as guide data is verified for the Forever client.
local OBJECTIVE_HINTS = {
    ["zenn's bidding"] = {
        ["nightsaber fang"] = "Kill Nightsabers to collect Nightsaber Fangs",
        ["strigid owl feather"] = "Kill Strigid Owls to collect Strigid Owl Feathers",
        ["webwood spider silk"] = "Kill Webwood Spiders to collect Webwood Spider Silk",
    },
}
local function objectiveDescription(quest,raw)
    if type(raw)~="string" then return raw end
    local hints=OBJECTIVE_HINTS[(quest.title or ""):lower()]
    if not hints then return raw end
    -- Quest objectives may include a trailing Blizzard progress counter.
    local key=raw:lower():gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    key=key:gsub("^%s+", ""):gsub("%s+$", "")
    return hints[key] or raw
end

-- Objective presentation: distinguish measurable counters, profession training,
-- and one-time actions. Do not treat an event-style 1/1 as measurable progress.
local ONE_TIME_ACTIONS = {
    "learn", "speak", "talk", "visit", "explore", "discover", "return",
    "deliver", "meet", "find", "read", "interact", "listen", "report",
}
local function isOneTimeObjective(description,o,total)
    if total ~= 1 then return false end
    local lower=(description or ""):lower()
    for _,verb in ipairs(ONE_TIME_ACTIONS) do
        if lower:match("^%s*"..verb.."%f[%A]") then return true end
    end
    -- Blizzard's event/trigger objectives have no accumulating count.
    local kind=tostring(o.type or o.objectiveType or ""):lower()
    return kind=="event" or kind=="trigger"
end
local function professionSkillLevel(name)
    local wanted=name:lower()
    -- On clients exposing legacy skill lines, this also covers secondary skills.
    if type(GetNumSkillLines)=="function" and type(GetSkillLineInfo)=="function" then
        local n=safe(GetNumSkillLines)
        if type(n)=="number" then
            for i=1,n do
                local skill,isHeader,_,rank=safe(GetSkillLineInfo,i)
                if type(skill)=="string" and not isHeader and skill:lower()==wanted
                    and type(rank)=="number" then
                    return rank
                end
            end
        end
    end
    -- Modern profession APIs may exist on supported Classic derivatives.
    if type(GetProfessions)=="function" and type(GetProfessionInfo)=="function" then
        local professions={safe(GetProfessions)}
        for i=1,6 do
            local id=professions[i]
            if type(id)=="number" then
                local skill,_,rank=safe(GetProfessionInfo,id)
                if type(skill)=="string" and skill:lower()==wanted and type(rank)=="number" then
                    return rank
                end
            end
        end
    end
    return nil
end
local function objectivePresentation(o,description,count,total,done)
    -- Parse only unambiguous skill targets: never fabricate the player's rank.
    local normalized=(description or ""):lower():gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    local skill,target=normalized:match("^%s*raise%s+your%s+([%a%s]+)%s+skill%s+to%s+(%d+)%s*%.?%s*$")
    if skill and target then
        skill=skill:match("^%s*(.-)%s*$")
        target=tonumber(target)
        if target and target>0 then
            local rank=professionSkillLevel(skill)
            if rank then
                return rank,target,(rank>=target),true
            end
            -- No reliable skill API: show the objective, without fake 1/1.
            return nil,nil,done,false
        end
    end
    if isOneTimeObjective(description,o,total) then
        return nil,nil,done,false
    end
    return count,total,done,(count~=nil and total~=nil and total>0)
end

local function questTitleFromLog(index)
    local name,level,tag,header,collapsed,complete,frequency,questID
    if C_QuestLog and C_QuestLog.GetInfo then
        local info=safe(C_QuestLog.GetInfo,index)
        if type(info)=="table" then
            return info.title or info.name,info.level,info.isHeader,info.questID,info.isComplete
        end
    end
    if GetQuestLogTitle then
        name,level,tag,header,collapsed,complete,frequency,questID=safe(GetQuestLogTitle,index)
        return name,level,header,questID,complete
    end
end
local function timerSeconds(value)
    -- Zero is a valid expired timer until the client removes its timer record.
    if type(value)=="number" and value==value and value>=0 and value<math.huge then return value end
end
local function readQuestTimers(entries)
    -- Forever returns { questID, questTimer } records. Never associate the
    -- positional results of legacy GetQuestTimers() with quest-log ordering.
    local timers=C_QuestLog and safe(C_QuestLog.GetQuestTimers)
    if type(timers)=="table" then
        local byID={}
        for _,timer in pairs(timers) do
            if type(timer)=="table" and type(timer.questID)=="number" then
                byID[timer.questID]=timerSeconds(timer.questTimer)
            end
        end
        for _,q in ipairs(entries) do q.timeLeft=q.id and byID[q.id] or nil end
        return
    end
    if C_QuestLog and type(C_QuestLog.GetTimeAllowed)=="function" then
        for _,q in ipairs(entries) do
            if q.id then
                local total,elapsedTime=safe(C_QuestLog.GetTimeAllowed,q.id)
                if timerSeconds(total) and total>0 and timerSeconds(elapsedTime) then
                    q.timeLeft=math.max(0,total-elapsedTime)
                end
            end
        end
        return
    end
    -- Older clients read the selected log entry, even if passed an index.
    -- Preserve selection and use only data APIs, never native UI selection helpers.
    if type(GetQuestLogTimeLeft)~="function" or type(SelectQuestLogEntry)~="function"
        or (InCombatLockdown and InCombatLockdown()) then return end
    local selected=safe(GetQuestLogSelection)
    if type(selected)~="number" or selected<=0 then return end
    for _,q in ipairs(entries) do
        local ok,result=pcall(SelectQuestLogEntry,q.index)
        if ok and result~=false and safe(GetQuestLogSelection)==q.index then
            q.timeLeft=timerSeconds(safe(GetQuestLogTimeLeft))
        end
    end
    safe(SelectQuestLogEntry,selected)
end
local function timerText(seconds)
    if seconds==nil then return "" end
    local whole=math.ceil(seconds)
    if whole>=3600 then
        return string.format(" (%d:%02d:%02d)",math.floor(whole/3600),math.floor(whole/60)%60,whole%60)
    end
    return string.format(" (%d:%02d)",math.floor(whole/60),whole%60)
end
local function snapshot()
    if db.showQuestItems then QuestItems:Refresh() end
    local entries={}
    local total=0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local a=safe(C_QuestLog.GetNumQuestLogEntries)
        if type(a)=="number" then total=a end
    end
    if total==0 and GetNumQuestLogEntries then
        local a=safe(GetNumQuestLogEntries)
        if type(a)=="number" then total=a end
    end
    for i=1,total do
        local name,level,header,id,complete=questTitleFromLog(i)
        if name and not header then
            if type(id)~="number" or id<=0 then id=nil end
            local e={index=i,id=id,title=name,level=tonumber(level) or 0,complete=complete==true or complete==1}
            e.key=id and ("quest:"..id) or ("index:"..i)
            if id and C_QuestLog and C_QuestLog.IsComplete then
                local done=safe(C_QuestLog.IsComplete,id)
                if done~=nil then e.complete=done==true or done==1 end
            end
            entries[#entries+1]=e
        end
    end
    readQuestTimers(entries)
    local watches={}
    if C_QuestLog then
        local num=safe(C_QuestLog.GetNumQuestWatches)
        if type(num)=="number" then
            for i=1,num do
                local id=safe(C_QuestLog.GetQuestIDForQuestWatchIndex,i)
                if not id and C_QuestLog.GetQuestWatchInfo then
                    local info=safe(C_QuestLog.GetQuestWatchInfo,i)
                    if type(info)=="table" then id=info.questID end
                end
                if type(id)=="number" and id>0 then watches[id]=true end
            end
        end
    end
    if GetNumQuestWatches and GetQuestIndexForWatch then
        local num=safe(GetNumQuestWatches)
        if type(num)=="number" then
            for i=1,num do
                local idx=safe(GetQuestIndexForWatch,i)
                if type(idx)=="number" and idx>0 then
                    local _,_,_,id=questTitleFromLog(idx)
                    if id then watches[id]=true else watches["index:"..idx]=true end
                end
            end
        end
    end
    local hasWatch=next(watches)~=nil
    local watchAPIAvailable = (C_QuestLog and type(C_QuestLog.GetNumQuestWatches)=="function") or (type(GetNumQuestWatches)=="function" and type(GetQuestIndexForWatch)=="function")
    local result={}
    for _,e in ipairs(entries) do
        local watched=watches[e.id] or watches["index:"..e.index]
        if not watched and C_QuestLog and C_QuestLog.IsQuestWatched and e.id then
            watched=safe(C_QuestLog.IsQuestWatched,e.id)==true
        end
        -- Some Forever builds expose log entries but no watch-list API.
        if not db.trackedOnly or watched or (not watchAPIAvailable) then
            e.watched=watched==true
            local objectives={}
            if e.id and C_QuestLog and C_QuestLog.GetQuestObjectives then
                local obj=safe(C_QuestLog.GetQuestObjectives,e.id)
                if type(obj)=="table" then objectives=obj end
            end
            if #objectives==0 and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
                local n=safe(GetNumQuestLeaderBoards,e.index) or 0
                for j=1,math.min(n,12) do
                    local txt,kind,done=safe(GetQuestLogLeaderBoard,j,e.index)
                    if txt then objectives[#objectives+1]={text=txt,finished=done} end
                end
            end
            e.objectives=objectives
            e.items=db.showQuestItems and QuestItems:ForQuest(e) or {}
            -- A descriptive objective may be the only quest objective.
            if #objectives==0 and e.id and C_QuestLog and C_QuestLog.GetQuestLogQuestText then
                local txt=safe(C_QuestLog.GetQuestLogQuestText,e.id)
                if type(txt)=="string" then e.description=txt end
            end
            result[#result+1]=e
        end
    end
    return result,entries
end

local function isCollapsed(q)
    local state=q.state
    if q.complete and state then
        if state.manualCollapsed~=nil then return state.manualCollapsed end
        if state.autoCollapsed then return true end
    end
    return db.collapsed[tostring(q.id or q.index)]==true
end

local function makeButton(parent,text,onClick)
    local b=CreateFrame("Button",nil,parent)
    backing(b,COLORS.surface)
    local highlight=b:CreateTexture(nil,"HIGHLIGHT")
    highlight:SetAllPoints(b)
    color(highlight,COLORS.blue,0.17)
    b.text=fontString(b,12,COLORS.white,"CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetJustifyV("MIDDLE")
    b.text:SetText(text)
    b:SetScript("OnClick",onClick)
    return b
end
-- Use the client's own super-tracking system so map/minimap navigation stays native.
local function superTrackedQuest()
    if C_SuperTrack and type(C_SuperTrack.GetSuperTrackedQuestID)=="function" then
        return safe(C_SuperTrack.GetSuperTrackedQuestID)
    end
    if type(GetSuperTrackedQuestID)=="function" then
        return safe(GetSuperTrackedQuestID)
    end
    return nil
end
local function setSuperTrackedQuest(questID)
    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID)=="function" then
        return pcall(C_SuperTrack.SetSuperTrackedQuestID,questID)
    end
    if type(SetSuperTrackedQuestID)=="function" then
        return pcall(SetSuperTrackedQuestID,questID)
    end
    return false
end
local function markerTooltip(marker)
    if not GameTooltip or not marker.quest then return end
    GameTooltip:SetOwner(marker,"ANCHOR_LEFT")
    local q=marker.quest
    if not q.id or not ((C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID)=="function") or type(SetSuperTrackedQuestID)=="function") then
        GameTooltip:SetText("Quest tracking unavailable on this client")
    elseif superTrackedQuest()==q.id then
        GameTooltip:SetText("Click to stop tracking")
    else
        GameTooltip:SetText("Click to track")
    end
    GameTooltip:Show()
end
local QUEST_RING="Interface\\AddOns\\XenQuest\\Media\\QuestRing"
local SETTINGS_GEAR="Interface\\AddOns\\XenQuest\\Media\\SettingsGear"
local function shareQuest(q)
    local link=BlizzardUI:QuestLink(q,questTitleFromLog)
    if link then safe(ChatEdit_InsertLink,link) end
end
local function titleCanNavigate(row)
    return row.quest and not row.motion and not row.returnMotion and not row.quest.state.animation
        and (row.paintAlpha or 1)>0.95
end
local function createRow(parent)
    local row=CreateFrame("Button",nil,parent)
    row:SetHeight(54)
    row:EnableMouse(true)
    row.head=fontString(row,13,COLORS.gold)
    row.head:SetPoint("TOPLEFT",26,-2)
    row.head:SetJustifyV("TOP")
    row.titleButton=CreateFrame("Button",nil,row)
    row.titleButton:SetPoint("TOPLEFT",row,"TOPLEFT",26,-2)
    row.titleButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row.titleButton:SetScript("OnMouseDown",function(self)
        self.pressedKey=titleCanNavigate(row) and row.quest.key or nil
    end)
    row.titleButton:SetScript("OnClick",function(self,button)
        local pressed=self.pressedKey
        self.pressedKey=nil
        if not row.quest or pressed~=row.quest.key or not titleCanNavigate(row) then return end
        if button=="RightButton" then row:GetScript("OnClick")(row,button);return end
        if IsShiftKeyDown and IsShiftKeyDown() then shareQuest(row.quest);return end
        -- Completed quests can be expanded/collapsed with a normal title click.
        -- Incomplete quest titles still open the quest log as before.
        if row.quest.complete then
            row:GetScript("OnClick")(row,"RightButton")
            return
        end
        local ok,message=BlizzardUI:OpenQuest(row.quest,questTitleFromLog)
        if not ok then print("|cffe8bb59XenQuest|r "..message) end
    end)
    row.shimmer=row:CreateTexture(nil,"OVERLAY")
    row.shimmer:SetTexture("Interface\\AddOns\\XenQuest\\Media\\CompletionShimmer")
    row.shimmer:SetVertexColor(COLORS.green[1],COLORS.green[2],COLORS.green[3])
    if row.shimmer.SetBlendMode then row.shimmer:SetBlendMode("ADD") end
    row.shimmer:Hide()
    row.bubble=CreateFrame("Button",nil,row)
    row.bubble:SetSize(24,26)
    row.bubble:SetPoint("TOPLEFT",1,-1)
    row.bubble.glow=row.bubble:CreateTexture(nil,"BACKGROUND")
    row.bubble.glow:SetTexture(QUEST_RING)
    row.bubble.glow:SetAllPoints(row.bubble)
    row.bubble.glow:SetVertexColor(1,0.88,0.43,0.18)
    row.bubble.glow:Hide()
    row.bubble.ring=row.bubble:CreateTexture(nil,"ARTWORK")
    row.bubble.ring:SetTexture(QUEST_RING)
    row.bubble.ring:SetAllPoints(row.bubble)
    row.bubble.ring:Hide()
    row.bubble:EnableMouse(true)
    row.bubble:RegisterForClicks("LeftButtonUp")
    row.bubble:SetScript("OnEnter",function(self) markerTooltip(self) end)
    row.bubble:SetScript("OnLeave",function(self) if GameTooltip then GameTooltip:Hide() end end)
    row.bubble:SetScript("OnClick",function(self)
        local q=self.quest
        if not q or not q.id then return end
        local target=(superTrackedQuest()==q.id) and 0 or q.id
        if setSuperTrackedQuest(target) then
            -- Update immediately; the event/periodic refresh also catches external changes.
            dirty=true
            markerTooltip(self)
        end
    end)
    row.symbol=fontString(row.bubble,20,COLORS.gold,"CENTER")
    row.symbol:ClearAllPoints()
    row.symbol:SetPoint("CENTER",row.bubble,"CENTER",0,0)
    row.symbol:SetWidth(24)
    row.symbol:SetHeight(26)
    row.symbol:SetJustifyH("CENTER")
    row.symbol:SetJustifyV("MIDDLE")
    row.symbol:SetText("!")
    -- A second, slightly larger glyph gives a soft glow without adding a circle.
    row.bubble.halo=fontString(row.bubble,22,COLORS.gold,"CENTER")
    row.bubble.halo:SetDrawLayer("BACKGROUND")
    row.bubble.halo:SetPoint("CENTER",row.bubble,"CENTER",0,0)
    row.bubble.halo:SetSize(28,30)
    row.bubble.halo:SetJustifyV("MIDDLE")
    row.bubble.halo:SetAlpha(0.38)
    row.bubble.halo:Hide()
    row.objectives={}
    row:SetScript("OnClick",function(self,btn)
        if not self.quest then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            shareQuest(self.quest)
            return
        end
        if btn=="RightButton" then
            local key=tostring(self.quest.id or self.quest.index)
            local collapsed=not isCollapsed(self.quest)
            db.collapsed[key]=collapsed
            if self.quest.complete then self.quest.state.manualCollapsed=collapsed end
        else
            db.primaryQuest=(self.quest and (self.quest.id or self.quest.index)) or 0
        end
        dirty=true
    end)
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    return row
end
local function objectiveWidget(row,index)
    if row.objectives[index] then return row.objectives[index] end
    local w=CreateFrame("Frame",nil,row)
    w.text=fontString(w,11,COLORS.white)
    w.text:SetPoint("TOPLEFT",0,0)
    w.text:SetJustifyV("TOP")
    w.amount=fontString(w,11,COLORS.muted,"RIGHT")
    w.amount:SetPoint("TOPRIGHT",0,0)
    w.track=CreateFrame("Frame",nil,w)
    w.track:SetHeight(6)
    w.track:SetPoint("TOPLEFT",0,-17)
    w.track:SetPoint("TOPRIGHT",0,-17)
    backing(w.track,COLORS.barbg)
    w.fill=w.track:CreateTexture(nil,"ARTWORK")
    w.fill:SetPoint("TOPLEFT",w.track,"TOPLEFT")
    w.fill:SetHeight(6)
    row.objectives[index]=w
    return w
end
local function measuredHeight(fontString,minimum)
    local h=safe(fontString.GetStringHeight,fontString)
    if type(h)~="number" or h<1 then return minimum end
    return math.max(minimum,math.ceil(h))
end
local function updateRow(row,q,width)
    row.quest=q
    row.bubble.quest=q
    local completed=q.complete
    local headingColor=completed and COLORS.green or COLORS.gold
    row.head.xqColor=headingColor
    row.symbol.xqColor=headingColor
    row.symbol:SetText(completed and "?" or "!")
    row.bubble.ring:Hide()
    row.bubble.glow:Hide()
    local activelyTracked=q.id and superTrackedQuest()==q.id
    row.bubble.halo:SetShown(activelyTracked and true or false)
    if activelyTracked then
        row.bubble.halo:SetText(completed and "?" or "!")
        row.bubble.halo.xqColor=headingColor
        applyFont(row.bubble.halo,22,"OUTLINE")
        row.bubble.halo:SetTextColor(headingColor[1],headingColor[2],headingColor[3])
        row.bubble.halo:SetShadowColor(headingColor[1],headingColor[2],headingColor[3],0.85)
        row.bubble.halo:SetShadowOffset(0,0)
    end
    local itemWidth=ItemButtons:UpdateRow(row,q,db.showQuestItems)
    row.head:SetWidth(math.max(80,width-32-itemWidth))
    -- Subtle emphasis: standard Blizzard font with a light monochrome outline.
    applyFont(row.head,13,"OUTLINE")
    row.head:SetShadowColor(0,0,0,0.65)
    row.head:SetShadowOffset(1,-1)
    row.head:SetText("["..tostring(q.level or "?").."] "..q.title..timerText(q.timeLeft))
    row.titleButton:SetSize(row.head:GetWidth(),measuredHeight(row.head,17))
    -- Apply the same selected font and outline as quest titles, only larger.
    -- The old marker had a malformed font path, silently leaving its tiny font in place.
    applyFont(row.symbol,18,"OUTLINE")
    row.symbol:SetTextColor(headingColor[1],headingColor[2],headingColor[3])
    row.symbol:SetShadowColor(0,0,0,0.95)
    row.symbol:SetShadowOffset(1,-1)
    -- The title can wrap, so objectives must begin below its actual height.
    local yy=math.max(28,measuredHeight(row.head,17)+10)
    row.titleHeight=yy
    local collapsed=isCollapsed(q)
    local active=0
    if not collapsed then
        for i,o in ipairs(q.objectives or {}) do
            if i>12 then break end
            local description,count,total,done=formatStatus(o)
            local showBar
            count,total,done,showBar=objectivePresentation(o,description,count,total,done)
            local w=objectiveWidget(row,i)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT",row,"TOPLEFT",26,-yy)
            local widgetWidth=math.max(90,width-32)
            w:SetWidth(widgetWidth)
            w.text.xqColor=COLORS.white
            w.amount.xqColor=done and COLORS.green or COLORS.muted
            applyFont(w.text,11)
            applyFont(w.amount,11)
            local hasCount=showBar
            local countWidth=hasCount and 45 or 0
            w.text:SetWidth(widgetWidth-countWidth-5)
            w.amount:SetWidth(countWidth)
            w.text:SetText(objectiveDescription(q,description))
            w.amount:SetText(hasCount and (count.."/"..total) or (done and "Done" or ""))
            local textHeight=measuredHeight(w.text,14)
            if hasCount then
                local barOffset=textHeight+5
                w.track:ClearAllPoints()
                w.track:SetPoint("TOPLEFT",w,"TOPLEFT",0,-barOffset)
                w.track:SetPoint("TOPRIGHT",w,"TOPRIGHT",0,-barOffset)
                w.track:Show()
                w.fill:SetWidth(math.max(0.01,widgetWidth*math.min(1,math.max(0,count/total))))
                color(w.fill,done and COLORS.green or COLORS.gold)
                local itemHeight=barOffset+6+7
                w:SetHeight(itemHeight)
                yy=yy+itemHeight
            else
                w.track:Hide()
                local itemHeight=textHeight+7
                w:SetHeight(itemHeight)
                yy=yy+itemHeight
            end
            w:Show()
            active=i
        end
        if active==0 then
            local w=objectiveWidget(row,1)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT",row,"TOPLEFT",26,-yy)
            local widgetWidth=math.max(90,width-32)
            w:SetWidth(widgetWidth)
            w.text:SetWidth(widgetWidth)
            w.amount:SetText("")
            w.track:Hide()
            local desc=q.description
            if not desc or desc=="" then desc=completed and "Ready to turn in" or "Quest in progress" end
            applyFont(w.text,11)
            w.text:SetText(desc)
            local itemHeight=measuredHeight(w.text,14)+8
            w:SetHeight(itemHeight)
            w:Show()
            active=1
            yy=yy+itemHeight
        end
    end
    for i=active+1,#row.objectives do row.objectives[i]:Hide() end
    row:SetHeight(yy+3)
    return yy+3
end
local function hideBlizzardTracker()
    BlizzardUI:SetSuppressed(db.hideBlizzard)
end
local function smooth(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
end
local function placeRow(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",tracker.content,"TOPLEFT",5+(row.x or 0),-row.y)
end
local function resetShimmer(row)
    row.shimmer:Hide()
    local c=row.head.xqColor
    row.head:SetTextColor(c[1],c[2],c[3])
    row.symbol:SetTextColor(c[1],c[2],c[3])
    row.head:SetShadowColor(0,0,0,0.65)
    row.head:SetShadowOffset(1,-1)
    row.symbol:SetShadowColor(0,0,0,0.95)
    row.symbol:SetShadowOffset(1,-1)
end
local function shimmer(row,age)
    if age>=SHIMMER_END then resetShimmer(row);return end
    local t=age/SHIMMER_END
    local glow=math.sin(math.pi*t)
    local c=COLORS.green
    row.head:SetTextColor(c[1]+0.25*glow,c[2]+0.12*glow,c[3]+0.22*glow)
    row.symbol:SetTextColor(c[1]+0.25*glow,c[2]+0.12*glow,c[3]+0.22*glow)
    row.head:SetShadowColor(c[1],c[2],c[3],0.8*glow)
    row.head:SetShadowOffset(0,0)
    row.symbol:SetShadowColor(c[1],c[2],c[3],glow)
    row.symbol:SetShadowOffset(0,0)
    local width=row:GetWidth()
    local band=math.min(80,width*0.3)
    row.shimmer:SetSize(band,row.titleHeight)
    row.shimmer:ClearAllPoints()
    row.shimmer:SetPoint("TOPLEFT",row,"TOPLEFT",(width-band)*smooth(t),0)
    row.shimmer:SetAlpha(0.38*glow)
    row.shimmer:Show()
end
local function updateScrollExtent()
    -- Keep the travelling rows inside the scroll child's extent until they settle.
    local extent=layoutHeight
    for _,q in ipairs(renderedQuestIDs) do
        local row=rows[q.key]
        extent=math.max(extent,row.y+row:GetHeight()+3)
    end
    tracker.content:SetHeight(math.max(1,extent))
    local maxScroll=math.max(0,extent-tracker.scroll:GetHeight())
    local scroll=tracker.scroll:GetVerticalScroll() or 0
    if scroll>maxScroll then tracker.scroll:SetVerticalScroll(maxScroll) end
end
local function presentRows()
    -- A 12px sidestep cannot pass a full-width neighbour without intersecting it.
    -- Briefly mask only the crossed neighbour, fading at the edges of the pass.
    -- The completing row itself stays visible and its actual frame keeps moving.
    for i,row in ipairs(paintOrder) do
        local alpha=1
        for j=1,i-1 do
            local other=paintOrder[j]
            if (row.motion or other.motion or row.quest.state.animation or other.quest.state.animation)
                and other.paintAlpha>0 then
                local gap=math.max(row.y-(other.y+other:GetHeight()),other.y-(row.y+row:GetHeight()))
                alpha=math.min(alpha,smooth(gap/3))
            end
        end
        row.paintAlpha=alpha
        row:SetAlpha(alpha)
        row:EnableMouse(alpha>0.95)
        row.bubble:EnableMouse(alpha>0.95)
        local navigate=titleCanNavigate(row)
        row.titleButton:EnableMouse(navigate and true or false)
        if not navigate then row.titleButton.pressedKey=nil end
        ItemButtons:MaskRow(row,alpha)
        if alpha<0.95 and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row.bubble) then
            GameTooltip:Hide()
        end
        local animation=row.quest.state.animation
        if animation then shimmer(row,animation.age) else resetShimmer(row) end
    end
    updateScrollExtent()
    ItemButtons:Sync(tracker,db)
end
layoutRows=function(snap)
    local width=db.width-26
    local y,delay=0,0
    for _,q in ipairs(renderedQuestIDs) do
        local a=q.state.animation
        if a then delay=math.max(delay,GLIDE_START-a.age) end
    end
    paintOrder={}
    for rank,q in ipairs(renderedQuestIDs) do
        local row=rows[q.key]
        row.rank=rank
        row:SetWidth(width)
        local h=updateRow(row,q,width)
        if snap or row.y==nil then
            row.y,row.x,row.motion=y,0,nil
            row.returnMotion=nil
        elseif row.targetY~=y then
            local a=q.state.animation
            local wait=a and math.max(0,GLIDE_START-a.age) or delay
            local duration=a and math.max(0.12,GLIDE_END-a.age-wait) or (delay>0 and GLIDE_END-GLIDE_START or 0.30)
            row.motion={from=row.y,to=y,age=0,delay=wait,duration=duration}
        end
        row.targetY=y
        placeRow(row)
        row:Show()
        paintOrder[#paintOrder+1]=row
        y=y+h+3
    end
    -- Drawing priority is independent of quest data and target layout order.
    table.sort(paintOrder,function(a,b)
        local aa,bb=a.quest.state.animation,b.quest.state.animation
        if aa and bb then return aa.serial<bb.serial end
        if aa or bb then return aa~=nil end
        return a.rank<b.rank
    end)
    layoutHeight=y
    presentRows()
end
finishAnimations=function()
    for _,state in pairs(questStates) do
        if state.animation then
            state.animation=nil
            state.autoCollapsed=state.complete
        end
    end
    if tracker then layoutRows(true) end
end
local function animateRows(dt)
    local relayout,active=false,false
    for _,q in ipairs(renderedQuestIDs) do
        local row,state=rows[q.key],q.state
        local a=state.animation
        if a then
            active=true
            row.returnMotion=nil
            local previous=a.age
            a.age=a.age+dt
            if previous<SHIMMER_END and a.age>=SHIMMER_END then
                state.autoCollapsed=true
                relayout=true
            end
            if a.age<SHIMMER_END then row.x=0
            elseif a.age<GLIDE_START then row.x=-12*smooth((a.age-SHIMMER_END)/(GLIDE_START-SHIMMER_END))
            elseif a.age<GLIDE_END then row.x=-12
            elseif a.age<ANIMATION_END then
                local t=(a.age-GLIDE_END)/(ANIMATION_END-GLIDE_END)-1
                row.x=12*(2.3*t*t*t+1.3*t*t)
            else
                row.x=0
                state.animation=nil
            end
        elseif row.x~=0 then
            -- A quest can become incomplete again during the sidestep.
            active=true
            local r=row.returnMotion or {from=row.x,age=0}
            row.returnMotion=r
            r.age=r.age+dt
            row.x=r.from*(1-smooth(r.age/0.18))
            if r.age>=0.18 then row.returnMotion=nil end
        end
        local m=row.motion
        if m then
            active=true
            m.age=m.age+dt
            local t=(m.age-m.delay)/m.duration
            row.y=m.from+(m.to-m.from)*smooth(t)
            if t>=1 then row.y=m.to;row.motion=nil end
        end
        if active then placeRow(row) end
    end
    if relayout then layoutRows(false)
    elseif active then presentRows() end
end
local function render()
    if not tracker or not db then return end
    local visible,entries=snapshot()
    ItemButtons.pending=false
    local states={}
    local trackerVisible=not db.minimized and tracker:IsShown() and (not tracker.IsVisible or tracker:IsVisible())
    local canAnimate=worldReady and not completionBaseline and trackerVisible
    -- Observe the whole log, including filtered quests. Missing IDs are pruned,
    -- never inferred to be completions. Index-only clients cannot prove identity.
    for _,q in ipairs(entries) do
        local previous=questStates[q.key]
        local state=previous or {complete=q.complete,autoCollapsed=q.complete}
        if previous and state.complete~=q.complete then
            state.animation=nil
            state.manualCollapsed=nil
            state.autoCollapsed=q.complete
            if q.id and q.complete and canAnimate and rows[q.key] then
                completionSerial=completionSerial+1
                state.autoCollapsed=false
                state.animation={age=0,serial=completionSerial}
            end
        end
        state.complete=q.complete
        q.state=state
        states[q.key]=state
    end
    questStates=states
    completionBaseline=false
    -- Stable partition preserves Blizzard order inside each completion group.
    local quests,completed,used={},{},{}
    for _,q in ipairs(visible) do
        if not used[q.key] then
            used[q.key]=true
            local group=q.complete and completed or quests
            group[#group+1]=q
        end
    end
    for _,q in ipairs(completed) do quests[#quests+1]=q end
    for key,row in pairs(rows) do
        if not used[key] then
            ItemButtons:Release(row)
            if row.quest.state.animation then
                row.quest.state.animation=nil
                row.quest.state.autoCollapsed=row.quest.complete
            end
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row.bubble) then GameTooltip:Hide() end
            row:Hide()
            row.titleButton.pressedKey=nil
            row.shimmer:Hide()
            row.quest,row.bubble.quest,row.motion,row.y,row.targetY,row.x=nil,nil,nil,nil,nil,0
            row.returnMotion=nil
            rows[key]=nil
            spareRows[#spareRows+1]=row
        end
    end
    for _,q in ipairs(quests) do
        if not rows[q.key] then rows[q.key]=table.remove(spareRows) or createRow(tracker.content) end
    end
    renderedQuestIDs=quests
    layoutRows(not trackerVisible)
    tracker.count:SetText(#quests.." quests")
    applyFont(tracker.count,10)
    if #quests==0 then
        tracker.empty:Show()
        tracker.empty:SetText(db.trackedOnly and "No watched quests. Track quests in Blizzard's quest log, or choose Show all in settings." or "Quest log is empty.")
        tracker.empty:SetWidth(db.width-26)
        applyFont(tracker.empty,11)
    else tracker.empty:Hide() end
    hideBlizzardTracker()
end
local function visualSettings()
    if not tracker then return end
    tracker:SetSize(db.width,db.minimized and 36 or db.height)
    tracker:SetScale(db.scale)
    color(tracker.background,COLORS.background,db.opacity)
    tracker.edge:SetAlpha(db.opacity)
    tracker.header:SetShown(db.showHeader)
    -- Extra breathing room between the header and first quest only.
    local inset=db.showHeader and 43 or 6
    tracker.scroll:ClearAllPoints()
    tracker.scroll:SetPoint("TOPLEFT",9,-inset)
    tracker.scroll:SetPoint("BOTTOMRIGHT",-12,10)
    tracker.scroll:SetShown(not db.minimized)
    if tracker.collapse and tracker.collapse.text then
        tracker.collapse.text:SetText(db.minimized and "+" or "-")
    end
    tracker.content:SetWidth(db.width-28)
    if db.minimized then finishAnimations() end
    dirty=true
end
local function createTracker()
    tracker=CreateFrame("Frame","XenQuestTracker",UIParent)
    tracker:SetSize(db.width,db.minimized and 36 or db.height)
    tracker:SetScale(db.scale)
    tracker:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",db.x,db.y)
    tracker:SetFrameStrata("LOW")
    tracker:SetScript("OnHide",function() ItemButtons:HideActions();finishAnimations();dirty=true end)
    tracker:SetScript("OnShow",function() finishAnimations();completionBaseline=true;dirty=true end)
    tracker:SetMovable(true)
    tracker:SetClampedToScreen(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart",function(self)
        if not db.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    tracker:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        -- GetRight/GetTop are in the frame's own effective scale. Convert
        -- both rectangles to screen pixels first, then back to parent units.
        -- This preserves the exact drop position at any UI/tracker scale.
        local parentScale=UIParent:GetEffectiveScale()
        local frameScale=self:GetEffectiveScale()
        local right=self:GetRight()
        local top=self:GetTop()
        local parentRight=UIParent:GetRight()
        local parentTop=UIParent:GetTop()
        if right and top and parentRight and parentTop and parentScale>0 then
            db.x=(right*frameScale-parentRight*parentScale)/parentScale
            db.y=(top*frameScale-parentTop*parentScale)/parentScale
            self:ClearAllPoints()
            self:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",db.x,db.y)
        end
    end)
    tracker.background=backing(tracker,COLORS.background)
    tracker.edge=tracker:CreateTexture(nil,"BORDER")
    tracker.edge:SetColorTexture(0.23,0.38,0.42,0.28)
    tracker.edge:SetPoint("TOPLEFT",0,0)
    tracker.edge:SetPoint("TOPRIGHT",0,0)
    tracker.edge:SetHeight(1)
    tracker.header=CreateFrame("Frame",nil,tracker)
    tracker.header:SetHeight(28)
    tracker.header:SetPoint("TOPLEFT",8,-5)
    tracker.header:SetPoint("TOPRIGHT",-8,-5)
    tracker.title=fontString(tracker.header,14,COLORS.gold)
    tracker.title:SetPoint("TOPLEFT",3,-4)
    tracker.title:SetText("XenQuest")
    tracker.title.xqSize=14
    local original=tracker.title
    tracker.count=fontString(tracker.header,10,COLORS.muted)
    tracker.count:SetPoint("TOPRIGHT",-29,-7)
    local gear=CreateFrame("Button",nil,tracker.header)
    gear:SetSize(24,24)
    gear:SetPoint("TOPRIGHT",0,2)
    gear.icon=gear:CreateTexture(nil,"ARTWORK")
    gear.icon:SetTexture(SETTINGS_GEAR)
    gear.icon:SetSize(17,17)
    gear.icon:SetPoint("CENTER")
    gear.icon:SetVertexColor(COLORS.muted[1],COLORS.muted[2],COLORS.muted[3],1)
    gear:SetScript("OnEnter",function(self)
        self.icon:SetVertexColor(COLORS.gold[1],COLORS.gold[2],COLORS.gold[3],1)
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText("XenQuest settings");GameTooltip:Show() end
    end)
    gear:SetScript("OnLeave",function(self)
        self.icon:SetVertexColor(COLORS.muted[1],COLORS.muted[2],COLORS.muted[3],1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    gear:SetScript("OnClick",function() if settings then settings:SetShown(not settings:IsShown()) end end)
    local collapse=CreateFrame("Button",nil,tracker.header)
    collapse:SetSize(27,27)
    collapse:SetPoint("RIGHT",gear,"LEFT",-2,0)
    collapse.text=fontString(collapse,23,COLORS.muted,"CENTER")
    collapse.text:SetAllPoints(collapse)
    collapse.text:SetJustifyV("MIDDLE")
    collapse.text:SetShadowColor(0,0,0,0.9)
    collapse.text:SetShadowOffset(1,-1)
    applyFont(collapse.text,23,"OUTLINE")
    collapse.text:SetText(db.minimized and "+" or "-")
    collapse:SetScript("OnEnter",function(self)
        self.text:SetTextColor(COLORS.gold[1],COLORS.gold[2],COLORS.gold[3])
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText(db.minimized and "Expand quests" or "Collapse quests");GameTooltip:Show() end
    end)
    collapse:SetScript("OnLeave",function(self)
        self.text:SetTextColor(COLORS.muted[1],COLORS.muted[2],COLORS.muted[3])
        if GameTooltip then GameTooltip:Hide() end
    end)
    collapse:SetScript("OnClick",function()
        db.minimized=not db.minimized
        if not db.minimized then completionBaseline=true end
        visualSettings()
    end)
    tracker.collapse=collapse
    tracker.count:ClearAllPoints()
    tracker.count:SetPoint("TOPRIGHT",collapse,"TOPLEFT",-5,-5)
    tracker.scroll=CreateFrame("ScrollFrame",nil,tracker)
    tracker.scroll:EnableMouseWheel(true)
    tracker.content=CreateFrame("Frame",nil,tracker.scroll)
    tracker.content:SetSize(db.width-28,1)
    tracker.scroll:SetScrollChild(tracker.content)
    tracker.scroll:SetScript("OnMouseWheel",function(self,delta)
        local current=self:GetVerticalScroll() or 0
        local visible=self:GetHeight() or 100
        local total=tracker.content:GetHeight() or 1
        self:SetVerticalScroll(math.max(0,math.min(math.max(0,total-visible),current-delta*55)))
        ItemButtons:Sync(tracker,db)
    end)
    tracker.empty=fontString(tracker.content,11,COLORS.muted)
    tracker.empty:SetPoint("TOPLEFT",8,-12)
    visualSettings()
    applyFont(original,14,"OUTLINE")
end
local function settingsTitle(parent,title,y)
    local t=fontString(parent,12,COLORS.gold)
    t:SetPoint("TOPLEFT",20,y)
    t:SetText(title)
    applyFont(t,12,"OUTLINE")
    return t
end
local function slider(parent,name,min,max,step,y,getValue,setValue,format)
    local lab=fontString(parent,12,COLORS.white)
    lab:SetPoint("TOPLEFT",22,y)
    local s=CreateFrame("Slider",nil,parent)
    s:SetPoint("TOPLEFT",22,y-22)
    s:SetSize(310,15)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min,max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local bg=backing(s,COLORS.surface)
    bg:SetHeight(5)
    bg:ClearAllPoints()
    bg:SetPoint("LEFT",s,"LEFT")
    bg:SetPoint("RIGHT",s,"RIGHT")
    local thumb=s:CreateTexture(nil,"ARTWORK")
    thumb:SetSize(12,18)
    color(thumb,COLORS.gold)
    s:SetThumbTexture(thumb)
    local function update(val)
        local display=format and format(val) or tostring(math.floor(val+0.5))
        lab:SetText(name..": "..display)
        applyFont(lab,12)
    end
    s:SetValue(getValue())
    update(getValue())
    s:SetScript("OnValueChanged",function(_,value)
        local rounded=math.floor(value/step+0.5)*step
        setValue(rounded)
        update(rounded)
        visualSettings()
    end)
    return s
end
local function toggle(parent,caption,y,get,set)
    local b=makeButton(parent,"",function(self)
        set(not get())
        self.text:SetText((get() and "[x] " or "[ ] ")..caption)
        visualSettings()
        hideBlizzardTracker()
    end)
    b:SetPoint("TOPLEFT",20,y)
    b:SetSize(320,25)
    b.text:SetText((get() and "[x] " or "[ ] ")..caption)
    applyFont(b.text,11)
    return b
end
local function createSettings()
    settings=CreateFrame("Frame","XenQuestSettings",UIParent)
    settings:SetSize(362,545)
    settings:SetPoint("CENTER",UIParent,"CENTER")
    settings:SetFrameStrata("DIALOG")
    settings:SetMovable(true)
    settings:EnableMouse(true)
    settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart",function(self) self:StartMoving() end)
    settings:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    backing(settings,COLORS.background)
    local heading=settingsTitle(settings,"XenQuest  /  SETTINGS",-18)
    local close=makeButton(settings,"X",function() settings:Hide() end)
    close:SetSize(24,24)
    close:SetPoint("TOPRIGHT",-12,-11)
    applyFont(close.text,12)
    slider(settings,"Background opacity",0,100,1,-55,function() return db.opacity*100 end,function(v) db.opacity=v/100 end,function(v) return tostring(math.floor(v+0.5)).."%" end)
    slider(settings,"UI scale",70,150,5,-113,function() return db.scale*100 end,function(v) db.scale=v/100 end,function(v) return tostring(v).."%" end)
    slider(settings,"Tracker width",260,520,10,-171,function() return db.width end,function(v) db.width=v end)
    slider(settings,"Tracker height",200,700,10,-229,function() return db.height end,function(v) db.height=v end)
    slider(settings,"Font size",10,18,1,-287,function() return db.fontSize end,function(v) db.fontSize=v end)
    local fontBtn=makeButton(settings,"",function(self)
        db.font=(db.font%#FONTS)+1
        self.text:SetText("Font: "..fontChoiceLabel().."  >")
        applyFont(self.text,12)
        visualSettings()
    end)
    fontBtn:SetPoint("TOPLEFT",20,-340)
    fontBtn:SetSize(322,29)
    fontBtn.text:SetText("Font: "..fontChoiceLabel().."  >")
    applyFont(fontBtn.text,12)
    local themeBtn=makeButton(settings,"",function(self)
        db.theme=(db.theme=="gold") and "ice" or "gold"
        if db.theme=="ice" then COLORS.gold={0.46,0.82,0.98} else COLORS.gold={0.96,0.77,0.36} end
        self.text:SetText("Accent theme: "..(db.theme=="ice" and "Icy blue" or "Warm gold").."  >")
        applyFont(self.text,12)
        visualSettings()
    end)
    themeBtn:SetPoint("TOPLEFT",20,-376)
    themeBtn:SetSize(322,28)
    themeBtn.text:SetText("Accent theme: "..(db.theme=="ice" and "Icy blue" or "Warm gold").."  >")
    applyFont(themeBtn.text,12)
    toggle(settings,"Hide Blizzard quest tracker",-410,function() return db.hideBlizzard end,function(v) db.hideBlizzard=v end)
    toggle(settings,"Show only watched quests",-439,function() return db.trackedOnly end,function(v) db.trackedOnly=v end)
    toggle(settings,"Lock tracker position",-468,function() return db.locked end,function(v) db.locked=v end)
    toggle(settings,"Show quest item buttons",-497,function() return db.showQuestItems end,function(v)
        db.showQuestItems=v
        if not v then ItemButtons:HideActions() else QuestItems:Invalidate() end
    end)
    settings:Hide()
end
local function initialize()
    if type(XenQuestDB)~="table" then XenQuestDB={} end
    db=XenQuestDB
    for k,v in pairs(DEFAULTS) do
        if db[k]==nil then
            if type(v)=="table" then db[k]={} else db[k]=v end
        end
    end
    if db.theme=="ice" then COLORS.gold={0.46,0.82,0.98} end
    -- Use the built-in WoW font by default, including for existing installations.
    if not db.blizzardFontResetApplied then
        db.font=1
        db.blizzardFontResetApplied=true
    end
    createTracker()
    createSettings()
    dirty=true
    print("|cffe8bb59XenQuest|r loaded. Use /xq for settings, /xq all to show every quest.")
end
SLASH_XENQUEST1="/xq"
SLASH_XENQUEST2="/xenquest"
SlashCmdList.XENQUEST=function(text)
    if not db then return end
    text=(text or ""):lower():match("^%s*(.-)%s*$")
    if text=="all" then db.trackedOnly=false;dirty=true
    elseif text=="tracked" then db.trackedOnly=true;dirty=true
    elseif text=="reset" then
        db.x,db.y=DEFAULTS.x,DEFAULTS.y
        tracker:ClearAllPoints()
        tracker:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",db.x,db.y)
        dirty=true
    elseif text=="show" then tracker:Show()
    elseif text=="hide" then tracker:Hide()
    else settings:SetShown(not settings:IsShown()) end
end
XQ:RegisterEvent("ADDON_LOADED")
XQ:RegisterEvent("PLAYER_ENTERING_WORLD")
XQ:RegisterEvent("QUEST_LOG_UPDATE")
XQ:RegisterEvent("QUEST_WATCH_UPDATE")
XQ:RegisterEvent("SUPER_TRACKING_CHANGED")
XQ:RegisterEvent("QUEST_ACCEPTED")
XQ:RegisterEvent("QUEST_REMOVED")
XQ:RegisterEvent("QUEST_TURNED_IN")
XQ:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
XQ:RegisterEvent("PLAYER_REGEN_ENABLED")
XQ:RegisterEvent("PLAYER_LOGOUT")
local itemEvents={"BAG_UPDATE","BAG_UPDATE_DELAYED","BAG_UPDATE_COOLDOWN","SPELL_UPDATE_COOLDOWN",
    "ITEM_LOCK_CHANGED","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT","PLAYER_REGEN_DISABLED",
    "ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED","CVAR_UPDATE","QUEST_TIMER_UPDATE"}
for _,event in ipairs(itemEvents) do pcall(XQ.RegisterEvent,XQ,event) end
XQ:SetScript("OnEvent",function(self,event,arg)
    if event=="ADDON_LOADED" then
        if arg==ADDON_NAME then initialize() end
        if db then hideBlizzardTracker() end
    elseif db then
        if event=="PLAYER_LOGOUT" then BlizzardUI:Shutdown();ItemButtons:HideActions();return end
        hideBlizzardTracker()
        if event=="BAG_UPDATE" or event=="BAG_UPDATE_DELAYED" or event=="ITEM_LOCK_CHANGED"
            or event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT"
            or event=="QUEST_LOG_UPDATE" or event=="QUEST_ACCEPTED" or event=="QUEST_REMOVED"
            or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" then
            QuestItems:Invalidate(event)
            ItemButtons:Invalidate()
        end
        if event=="PLAYER_ENTERING_WORLD" then
            worldReady=true
            completionBaseline=true
            finishAnimations()
        end
        dirty=true
    end
end)
XQ:SetScript("OnUpdate",function(self,dt)
    if not db or not tracker then return end
    animateRows(dt)
    ItemButtons:Sync(tracker,db)
    elapsed=elapsed+dt
    if elapsed<0.35 then return end
    elapsed=0
    if dirty then
        dirty=false
        local ok,err=pcall(render)
        if not ok then print("|cffff6666XenQuest display error:|r "..tostring(err)) end
    else
        -- An inexpensive periodic refresh also handles quest-watch changes
        -- that Forever's beta does not always announce as events.
        dirty=true
        hideBlizzardTracker()
    end
end)
