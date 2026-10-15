-- Run from the addon directory: lua Tests/Completion.lua (Lua 5.1).
-- Loads the real addon in isolated mock clients; no test code is loaded by the TOC.
local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,message)
end
local function quest(id,complete,watched)
    return {id=id,title="Same quest title",level=10,complete=complete or false,
        watched=watched~=false,objectives={{text="Collect items",numFulfilled=1,numRequired=3}}}
end
local function boot(log,modern,saved,configure)
    local env=setmetatable({SlashCmdList={},XenQuestDB=saved or {}},{__index=_G})
    env._G=env
    local objects={}
    local methods={}
    local function object(kind,parent)
        local o=setmetatable({kind=kind,parent=parent,scripts={},shown=true,width=300,height=100,alpha=1}, {__index=methods})
        objects[#objects+1]=o
        return o
    end
    -- Deliberately enumerate UI primitives: an accidental dependency on a new API fails.
    for name in ("SetJustifyH SetJustifyV SetShadowColor SetShadowOffset SetColorTexture SetAllPoints "..
        "SetTexture SetVertexColor SetBlendMode SetDrawLayer RegisterForClicks RegisterForDrag "..
        "SetMovable SetClampedToScreen SetFrameStrata SetOrientation SetMinMaxValues SetValueStep "..
        "SetThumbTexture EnableMouseWheel SetScrollChild StartMoving StopMovingOrSizing RegisterEvent"):gmatch("%S+") do
        methods[name]=function() end
    end
    function methods:SetScript(name,fn) self.scripts[name]=fn end
    function methods:GetScript(name) return self.scripts[name] end
    function methods:SetSize(w,h) self.width,self.height=w,h end
    function methods:SetWidth(w) self.width=w end
    function methods:SetHeight(h) self.height=h end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetPoint(...) self.point={...} end
    function methods:ClearAllPoints() self.point=nil end
    function methods:SetText(text) self.textValue=text end
    function methods:SetTextColor(...) self.textColor={...} end
    function methods:SetFont(path,size) self.fontSize=size;return true end
    function methods:GetStringHeight()
        local size=self.fontSize or 12
        return math.ceil(#(self.textValue or "")*size*0.5/self.width)*(size+2)
    end
    function methods:CreateTexture() return object("Texture",self) end
    function methods:CreateFontString() return object("FontString",self) end
    function methods:Show()
        local wasShown=self.shown
        self.shown=true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local wasShown=self.shown
        self.shown=false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:SetAlpha(alpha) self.alpha=alpha end
    function methods:EnableMouse(enabled) self.mouse=enabled end
    function methods:SetScale(scale) self.scale=scale end
    function methods:GetEffectiveScale() return self.scale or 1 end
    function methods:SetValue(v) self.value=v end
    function methods:SetVerticalScroll(v) self.scroll=v end
    function methods:GetVerticalScroll() return self.scroll or 0 end
    function methods:GetRight() return 1000 end
    function methods:GetTop() return 900 end
    env.UIParent=object("Frame")
    local driver
    env.CreateFrame=function(kind,name,parent)
        local o=object(kind,parent)
        if name then env[name]=o end
        if not driver then driver=o end
        return o
    end
    env.CreateFont=function() return object("Font") end
    env.print=function(message)
        if message:find("display error",1,true) then error(message) end
    end
    local tracked=0
    env.GetSuperTrackedQuestID=function() return tracked end
    env.SetSuperTrackedQuestID=function(id) tracked=id end
    local function byID(id)
        for _,q in ipairs(log) do if q.id==id then return q end end
    end
    local function watches()
        local result={}
        for i,q in ipairs(log) do if q.watched then result[#result+1]=i end end
        return result
    end
    if modern then
        env.C_QuestLog={
            GetNumQuestLogEntries=function() return #log end,
            GetInfo=function(i)
                local q=log[i]
                return {title=q.title,level=q.level,questID=q.id,isComplete=q.complete}
            end,
            IsComplete=function(id) return byID(id).complete end,
            GetQuestObjectives=function(id) return byID(id).objectives end,
            GetNumQuestWatches=function() return #watches() end,
            GetQuestIDForQuestWatchIndex=function(i) return log[watches()[i]].id end,
        }
    else
        env.GetNumQuestLogEntries=function() return #log end
        env.GetQuestLogTitle=function(i)
            local q=log[i]
            return q.title,q.level,nil,false,false,q.complete and 1 or nil,nil,q.id
        end
        env.GetNumQuestWatches=function() return #watches() end
        env.GetQuestIndexForWatch=function(i) return watches()[i] end
        env.GetNumQuestLeaderBoards=function(i) return #log[i].objectives end
        env.GetQuestLogLeaderBoard=function(j,i)
            local o=log[i].objectives[j]
            return o.text,"item",o.numFulfilled>=o.numRequired
        end
    end
    if configure then configure(env,objects,methods) end
    local addon={}
    for _,file in ipairs({"QuestItems.lua","QuestItemButtons.lua","BlizzardUI.lua","Core.lua"}) do
        local chunk=assert(loadfile(file))
        setfenv(chunk,env)("XenQuest",addon)
    end
    local h={env=env,log=log,objects=objects,addon=addon}
    function h:event(event,arg) driver.scripts.OnEvent(driver,event,arg) end
    function h:tick(dt)
        driver.scripts.OnUpdate(driver,dt)
        local ordered=self:order()
        for i,row in ipairs(ordered) do
            assert(row.y==row.y and row.y>=0,"invalid rendered position")
            if row.alpha>0 then
                for j=i+1,#ordered do
                    local other=ordered[j]
                    if other.alpha>0 then
                        assert(row.y+row:GetHeight()<=other.y or other.y+other:GetHeight()<=row.y,
                            "visible rows intersect during a transition")
                    end
                end
            end
        end
    end
    function h:advance(seconds)
        for i=1,math.ceil(seconds*120) do self:tick(1/120) end
    end
    function h:refresh() self:event("QUEST_LOG_UPDATE");self:advance(0.36) end
    function h:row(id)
        for _,o in ipairs(objects) do
            if o.kind=="Button" and o.head and o.quest and o.quest.id==id then return o end
        end
    end
    function h:order()
        local result={}
        for _,o in ipairs(objects) do
            if o.kind=="Button" and o.head and o.quest then result[#result+1]=o end
        end
        table.sort(result,function(a,b) return a.targetY<b.targetY end)
        return result
    end
    function h:settled()
        self:advance(2)
        local y=0
        for _,row in ipairs(self:order()) do
            check(not row.motion and not row.quest.state.animation,"animation did not finish")
            check(row.y==y and row.targetY==y and row.x==0,"settled layout has a gap or wrong position")
            check(row.alpha==1 and row.mouse and row.bubble.mouse,"mask or click state leaked")
            y=y+row:GetHeight()+3
        end
    end
    h:event("ADDON_LOADED","XenQuest")
    h:event("PLAYER_ENTERING_WORLD")
    h:refresh()
    return h
end

if ...=="harness" then return {boot=boot,quest=quest,check=check} end

for _,modern in ipairs({false,true}) do
    local log={quest(10,true),quest(20),quest(30),quest(40,true)}
    local h=boot(log,modern,{collapsed={["20"]=false}})
    local order=h:order()
    check(order[1].quest.id==20 and order[2].quest.id==30 and order[3].quest.id==10 and order[4].quest.id==40,"stable partition")
    check(not h:row(10).quest.state.animation and not h:row(10).objectives[1],"login completion must be collapsed without animation")
    local row=h:row(20)
    local initialY=row.y
    log[2].objectives[1].numFulfilled=3
    h:refresh()
    check(not row.quest.state.animation and not row.quest.complete,"objective progress is not overall completion")
    log[2].complete=true
    h:refresh()
    local animation=row.quest.state.animation
    check(animation~=nil and h:row(20)==row,"completion must animate the existing row")
    h:advance(0.18)
    check(row.quest.state.autoCollapsed and not row.objectives[1].shown,"collapse after shimmer")
    check(h.env.XenQuestDB.collapsed["20"]==false,"automatic collapse changed saved choice")
    h:advance(0.20)
    check(row.x<0,"bounce left missing")
    h:refresh()
    check(row.quest.state.animation==animation,"refresh reset animation identity")
    check(row.y>initialY and row.y<row.targetY,"actual row must glide between positions")
    h:advance(math.max(0,1.18-animation.age))
    check(row.x>0,"bounce right should briefly overshoot")
    h:settled()
    order=h:order()
    check(order[1].quest.id==30 and order[2].quest.id==10 and order[3].quest.id==20 and order[4].quest.id==40,"completed group must retain log order")
    row.scripts.OnClick(row,"RightButton")
    h:refresh()
    check(row.objectives[1].shown,"manual expansion of automatically collapsed quest")
    h:refresh()
    check(row.objectives[1].shown and not row.quest.state.animation,"refresh undid manual expansion or replayed animation")
    row.bubble.scripts.OnClick(row.bubble)
    h:refresh()
    check(h.env.GetSuperTrackedQuestID()==20 and row.bubble.halo.shown,"native marker tracking and halo")
    row.bubble.scripts.OnClick(row.bubble)
    h:refresh()
    check(h.env.GetSuperTrackedQuestID()==0,"native marker untracking")
    log[2].complete=false
    h:refresh()
    check(not row.quest.state.autoCollapsed and row.objectives[1].shown,"incomplete again must restore normal display")
    log[2].complete=true
    h:refresh()
    row.scripts.OnClick(row,"RightButton") -- manually collapse during shimmer
    row.scripts.OnClick(row,"RightButton") -- then explicitly expand
    h:settled()
    check(row.objectives[1].shown,"completion finish overwrote manual action")

    local a,b,c=quest(101),quest(102),quest(103)
    local rapid=boot({a,b,c},modern)
    local ar,br=rapid:row(101),rapid:row(102)
    a.complete=true
    rapid:refresh()
    local first=ar.quest.state.animation
    b.complete=true
    rapid:refresh()
    check(ar.quest.state.animation==first and br.quest.state.animation~=nil,"rapid completions lost or restarted")
    table.remove(rapid.log,1)
    rapid:refresh()
    check(rapid:row(101)==nil and not ar.shown and ar.motion==nil,"removed animated row not released")
    rapid:settled()
    table.insert(rapid.log,1,a)
    rapid:refresh()
    check(not rapid:row(101).quest.state.animation,"reappearing completed quest replayed animation")

    local hidden=quest(201,false,false)
    local filter=boot({hidden,quest(202)},modern)
    hidden.complete=true
    filter:refresh()
    filter.env.SlashCmdList.XENQUEST("all")
    filter:refresh()
    check(not filter:row(201).quest.state.animation,"settings exposed a false transition")
    filter.env.SlashCmdList.XENQUEST("hide")
    filter.log[2].complete=true
    filter:refresh()
    filter.env.SlashCmdList.XENQUEST("show")
    filter:refresh()
    check(not filter:row(202).quest.state.animation,"showing tracker replayed hidden completion")
    filter.log[2].complete=false
    filter:refresh()
    filter.env.SlashCmdList.XENQUEST("hide")
    filter.log[2].complete=true
    filter.env.SlashCmdList.XENQUEST("show") -- before the next polling refresh
    filter:refresh()
    check(not filter:row(202).quest.state.animation,"show before polling inferred a hidden completion")

    local minimized=boot({quest(301),quest(302)},modern)
    minimized.log[1].complete=true
    minimized:refresh()
    local tracker=minimized.env.XenQuestTracker
    tracker.collapse.scripts.OnClick()
    check(not minimized:row(301).quest.state.animation and minimized:row(301).quest.state.autoCollapsed,"minimize did not finish completion")
    tracker.collapse.scripts.OnClick()
    minimized:settled()
    tracker.collapse.scripts.OnClick()
    minimized.log[2].complete=true
    tracker.collapse.scripts.OnClick() -- before the next polling refresh
    minimized:refresh()
    check(not minimized:row(302).quest.state.animation,"expand before polling replayed completion")
    tracker.scroll:SetVerticalScroll(999)
    minimized:refresh()
    check(tracker.scroll:GetVerticalScroll()<=math.max(0,tracker.content:GetHeight()-tracker.scroll:GetHeight()),"scroll was not clamped")

    local reload=boot({quest(401,true),quest(402)},modern,{collapsed={["401"]=false}})
    reload:settled()
    check(not reload:row(401).quest.state.animation and reload:row(401).quest.state.autoCollapsed,"reload replayed completion")
    local count=#reload.objects
    for i=1,10 do
        table.remove(reload.log,1)
        reload:refresh()
        table.insert(reload.log,1,quest(401,true))
        reload:refresh()
    end
    check(#reload.objects==count,"row/texture pool grew after repeated removal and return")

    local simultaneous=boot({quest(601),quest(602),quest(603),quest(604)},modern)
    simultaneous.log[1].complete=true
    simultaneous.log[3].complete=true
    simultaneous:refresh()
    check(simultaneous:row(601).quest.state.animation and simultaneous:row(603).quest.state.animation,"simultaneous transitions lost")
    simultaneous.env.XenQuestDB.width=260
    simultaneous.env.XenQuestDB.fontSize=18
    simultaneous.log[2].title=string.rep("A long quest title ",8)
    simultaneous:refresh()
    simultaneous.log[1].complete=false -- reverse one completion during the glide
    simultaneous:refresh()
    check(not simultaneous:row(601).quest.state.animation,"reversal kept a completion animation alive")
    simultaneous:settled()
    check(simultaneous:row(601).objectives[1].shown,"reversal did not restore objectives")
    simultaneous.log[4].complete=true
    simultaneous:refresh()
    simultaneous:tick(3) -- low framerate / loading stall
    simultaneous:settled()
end

local fallback=boot({quest(nil),quest(502)},false)
fallback.log[1].complete=true
fallback:refresh()
local unknown=fallback:row(nil)
check(unknown.quest.state.autoCollapsed and not unknown.quest.state.animation,"index-only quest must not infer transition identity")
unknown.scripts.OnClick(unknown,"RightButton")
fallback:refresh()
check(unknown.objectives[1].shown,"index-only manual expansion did not survive refresh")

-- Deterministic mixed updates exercise retargeting and pooling under load.
math.randomseed(12345)
local stress=boot({quest(701),quest(702),quest(703),quest(704),quest(705)},true)
for i=1,400 do
    local q=stress.log[math.random(#stress.log)]
    local action=math.random(6)
    if action==1 then q.complete=not q.complete
    elseif action==2 then q.watched=not q.watched
    elseif action==3 then
        local row=stress:row(q.id)
        if row then row.scripts.OnClick(row,"RightButton") end
    elseif action==4 then
        stress.env.XenQuestDB.width=math.random(26,52)*10
        stress.env.XenQuestDB.fontSize=math.random(10,18)
    elseif action==5 then
        stress.env.XenQuestTracker.collapse.scripts.OnClick()
    else
        table.remove(stress.log,math.random(#stress.log))
        table.insert(stress.log,math.random(#stress.log+1),quest(800+i,math.random(2)==1))
    end
    stress:event("QUEST_LOG_UPDATE")
    stress:advance(0.05)
end
stress:settled()
print("PASS: "..checks.." completion/layout checks (legacy and C_QuestLog)")
