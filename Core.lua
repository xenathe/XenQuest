-- XenQuest 0.2.1-beta. Standalone quest tracker for WoW Forever / Classic-era clients.
-- Never changes the quest log or uses protected quest actions automatically.
local ADDON_NAME = ...
local XQ = CreateFrame("Frame")
local db, tracker, settings, rows = nil, nil, nil, {}
local dirty, elapsed, suppressDefault = true, 0, false
local renderedQuestIDs = {}

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
    theme="gold", primaryQuest=0, collapsed={}, minimized=false,
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
local function snapshot()
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
            local e={index=i,id=id,title=name,level=tonumber(level) or 0,complete=complete==true or complete==1}
            entries[#entries+1]=e
        end
    end
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
            if e.id and C_QuestLog and C_QuestLog.IsComplete then
                local done=safe(C_QuestLog.IsComplete,e.id)
                if done==true then e.complete=true end
            end
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
            -- A descriptive objective may be the only quest objective.
            if #objectives==0 and e.id and C_QuestLog and C_QuestLog.GetQuestLogQuestText then
                local txt=safe(C_QuestLog.GetQuestLogQuestText,e.id)
                if type(txt)=="string" then e.description=txt end
            end
            result[#result+1]=e
        end
    end
    return result
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
local QUEST_RING="Interface\\AddOns\\XenQuest\\Media\\QuestRing"
local SETTINGS_GEAR="Interface\\AddOns\\XenQuest\\Media\\SettingsGear"
local function createRow(parent)
    local row=CreateFrame("Button",nil,parent)
    row:SetHeight(54)
    row:EnableMouse(true)
    row.head=fontString(row,13,COLORS.gold)
    row.head:SetPoint("TOPLEFT",26,-2)
    row.head:SetJustifyV("TOP")
    row.bubble=CreateFrame("Frame",nil,row)
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
    row.symbol=fontString(row.bubble,20,COLORS.gold,"CENTER")
    row.symbol:ClearAllPoints()
    row.symbol:SetPoint("CENTER",row.bubble,"CENTER",0,0)
    row.symbol:SetWidth(24)
    row.symbol:SetHeight(26)
    row.symbol:SetJustifyH("CENTER")
    row.symbol:SetJustifyV("MIDDLE")
    row.symbol:SetText("!")
    row.objectives={}
    row:SetScript("OnClick",function(self,btn)
        if IsShiftKeyDown and IsShiftKeyDown() and self.quest and self.quest.id then
            local link=safe(GetQuestLink,self.quest.index)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            return
        end
        if btn=="RightButton" then
            local key=tostring(self.quest.id or self.quest.index)
            db.collapsed[key]=not db.collapsed[key]
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
    local completed=q.complete
    local headingColor=completed and COLORS.green or COLORS.gold
    row.head.xqColor=headingColor
    row.symbol.xqColor=headingColor
    row.symbol:SetText(completed and "?" or "!")
    row.bubble.ring:Hide()
    local selected=(q.id and db.primaryQuest==q.id) or (not q.id and db.primaryQuest==q.index)
    row.bubble.glow:SetShown(false)
    row.head:SetWidth(math.max(80,width-32))
    -- Subtle emphasis: standard Blizzard font with a light monochrome outline.
    applyFont(row.head,13,"OUTLINE")
    row.head:SetShadowColor(0,0,0,0.65)
    row.head:SetShadowOffset(1,-1)
    row.head:SetText("["..tostring(q.level or "?").."] "..q.title)
    -- Apply the same selected font and outline as quest titles, only larger.
    -- The old marker had a malformed font path, silently leaving its tiny font in place.
    applyFont(row.symbol,18,"OUTLINE")
    row.symbol:SetTextColor(headingColor[1],headingColor[2],headingColor[3])
    row.symbol:SetShadowColor(0,0,0,0.95)
    row.symbol:SetShadowOffset(1,-1)
    -- The title can wrap, so objectives must begin below its actual height.
    local yy=math.max(28,measuredHeight(row.head,17)+10)
    local collapsed=db.collapsed[tostring(q.id or q.index)]
    local active=0
    if not collapsed then
        for i,o in ipairs(q.objectives or {}) do
            if i>12 then break end
            local description,count,total,done=formatStatus(o)
            local w=objectiveWidget(row,i)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT",row,"TOPLEFT",26,-yy)
            local widgetWidth=math.max(90,width-32)
            w:SetWidth(widgetWidth)
            w.text.xqColor=COLORS.white
            w.amount.xqColor=done and COLORS.green or COLORS.muted
            applyFont(w.text,11)
            applyFont(w.amount,11)
            local hasCount=(count~=nil and total~=nil and total>0)
            local countWidth=hasCount and 45 or 0
            w.text:SetWidth(widgetWidth-countWidth-5)
            w.amount:SetWidth(countWidth)
            w.text:SetText(description)
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
    local frame=_G.ObjectiveTrackerFrame or _G.WatchFrame
    if not frame then return end
    if not db.hideBlizzard then
        if suppressDefault then
            pcall(frame.SetAlpha,frame,1)
            suppressDefault=false
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    local ok=pcall(frame.SetAlpha,frame,0)
    if ok then suppressDefault=true end
end
local function render()
    if not tracker or not db then return end
    local quests=snapshot()
    renderedQuestIDs=quests
    local innerWidth=db.width-26
    local y=0
    for i,q in ipairs(quests) do
        local row=rows[i]
        if not row then row=createRow(tracker.content);rows[i]=row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",tracker.content,"TOPLEFT",5,-y)
        row:SetWidth(innerWidth)
        local h=updateRow(row,q,innerWidth)
        row:Show()
        y=y+h+3
    end
    for i=#quests+1,#rows do rows[i]:Hide() end
    tracker.content:SetHeight(math.max(1,y))
    tracker.count:SetText(#quests.." quests")
    applyFont(tracker.count,10)
    if #quests==0 then
        tracker.empty:Show()
        tracker.empty:SetText(db.trackedOnly and "No watched quests. Track quests in Blizzard's quest log, or choose Show all in settings." or "Quest log is empty.")
        tracker.empty:SetWidth(innerWidth)
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
    dirty=true
end
local function createTracker()
    tracker=CreateFrame("Frame","XenQuestTracker",UIParent)
    tracker:SetSize(db.width,db.minimized and 36 or db.height)
    tracker:SetScale(db.scale)
    tracker:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",db.x,db.y)
    tracker:SetFrameStrata("LOW")
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
XQ:RegisterEvent("QUEST_ACCEPTED")
XQ:RegisterEvent("QUEST_REMOVED")
XQ:RegisterEvent("QUEST_TURNED_IN")
XQ:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
XQ:RegisterEvent("PLAYER_REGEN_ENABLED")
XQ:SetScript("OnEvent",function(self,event,arg)
    if event=="ADDON_LOADED" then
        if arg==ADDON_NAME then initialize() end
    elseif db then dirty=true end
end)
XQ:SetScript("OnUpdate",function(self,dt)
    if not db or not tracker then return end
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
