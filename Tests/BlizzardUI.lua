-- Run with Lua 5.1 from the addon directory; mock UI, not in-game certification.
local harness=assert(loadfile("Tests/Completion.lua"))("harness")
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function fixture(modern,options)
    options=options or {}
    local state={combat=options.combat,opens=0,selections=0,details=0,messages={},roots={}}
    local log={harness.quest(101),harness.quest(102,true),harness.quest(103)}
    local h=harness.boot(log,modern,nil,function(env,objects,methods)
        env.InCombatLockdown=function() return state.combat end
        function methods:IsForbidden() return self.forbidden or false end
        function methods:IsProtected() return self.protected or false end
        function methods:GetAlpha() assert(not self.forbidden);return self.alpha end
        function methods:IsMouseEnabled() assert(not self.forbidden);return self.mouse end
        function methods:GetParent() assert(not self.forbidden);return self.parent end
        function methods:HookScript(name,fn)
            assert(not self.forbidden and not (self.protected and state.combat))
            self.hooks=self.hooks or {}
            self.hooks[name]=self.hooks[name] or {}
            table.insert(self.hooks[name],fn)
        end
        for _,name in ipairs({"Show","Hide","SetAlpha","EnableMouse"}) do
            local original=methods[name]
            methods[name]=function(self,...)
                assert(not self.forbidden,"mutation of forbidden frame")
                assert(not (self.protected and state.combat) or state.native,"protected mutation in combat")
                local wasShown=self.shown
                self.writes=(self.writes or 0)+1
                original(self,...)
                if name=="Show" and not wasShown then
                    for _,hook in ipairs(self.hooks and self.hooks.OnShow or {}) do hook(self) end
                end
            end
        end
        local function frame(shown,parent)
            return setmetatable({kind="Frame",parent=parent or env.UIParent,scripts={},shown=shown,
                alpha=0.6,mouse=true,width=300,height=200},{__index=methods})
        end
        state.frame=frame
        for _,name in ipairs({"ObjectiveTrackerFrame","WatchFrame","QuestWatchFrame"}) do
            local root=frame(name~="QuestWatchFrame")
            root.protected=name=="WatchFrame"
            root.child=frame(true,root)
            state.roots[name]=root
            env[name]=root
        end
        env.GameTooltip={owner=env.ObjectiveTrackerFrame.child,shown=true}
        function env.GameTooltip:GetOwner() return self.owner end
        function env.GameTooltip:IsOwned(owner) return self.owner==owner end
        function env.GameTooltip:SetOwner(owner) self.owner=owner end
        function env.GameTooltip:SetText(text) self.text=text end
        function env.GameTooltip:Show() self.shown=true end
        function env.GameTooltip:Hide() self.shown=false end
        env.print=function(message)
            if message:find("display error",1,true) then error(message) end
            state.messages[#state.messages+1]=message
        end
        if not options.unsupported then
            if not options.map then
                env.QuestLogFrame=frame(false)
                env.ShowUIPanel=function(f)
                    state.opens=state.opens+1
                    f:Show()
                    if state.onOpen then state.onOpen() end
                end
                local function selectIndex(index)
                    check(log[index]~=nil,"selected a missing log index")
                    state.selectedID=log[index].id
                    state.selectedIndex=index
                    state.selections=state.selections+1
                end
                if modern then
                    env.C_QuestLog.SetSelectedQuest=function(id)
                        state.selectedID=id
                        state.selections=state.selections+1
                    end
                else env.QuestLog_SetSelection=selectIndex end
                env.QuestLog_Update=function() state.updates=(state.updates or 0)+1 end
                env.QuestLog_UpdateQuestDetails=function() state.details=state.details+1 end
            else
                env.QuestMapFrame=frame(false)
                env.QuestMapFrame_OpenToQuestDetails=function(id)
                    state.selectedID=id
                    state.opens=state.opens+1
                    state.details=state.details+1
                    env.QuestMapFrame:Show()
                end
            end
        end
        env.GetQuestLogIndexByID=function(id)
            if state.badIndex then return state.badIndex end
            for index,q in ipairs(log) do if q.id==id then return index end end
            return 0
        end
        if modern then env.C_QuestLog.GetLogIndexForQuestID=env.GetQuestLogIndexByID end
        env.IsShiftKeyDown=function() return state.shift end
        env.GetQuestLink=function(index)
            local id=state.idLinks and index or (log[index] and log[index].id)
            if id then return "|Hquest:"..id..":10|h[quest]|h" end
        end
        env.ChatEdit_InsertLink=function(link) state.chatLink=link end
    end)
    function state:combatChange(value)
        self.combat=value
        h:event(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    function state:showNative(root)
        -- Simulate Blizzard's secure Show; the addon hook is still insecure.
        self.native=true
        local wasShown=root.shown
        root.shown=true
        self.native=false
        if not wasShown then
            for _,hook in ipairs(root.hooks and root.hooks.OnShow or {}) do hook(root) end
        end
    end
    return h,state
end
local function click(row,button)
    row.titleButton.scripts.OnMouseDown(row.titleButton)
    row.titleButton.scripts.OnClick(row.titleButton,button or "LeftButton")
end

local h,s=fixture(false)
for _,root in pairs(s.roots) do
    check(not root:IsShown() and not root.child:IsVisible(),"tracker descendants remain interactive")
    check(root.alpha==0.6 and root.mouse and root.child.mouse,"suppression changed unrelated appearance/input flags")
end
check(not h.env.GameTooltip.shown,"existing descendant tooltip persisted")
local root=s.roots.ObjectiveTrackerFrame
local writes=root.writes
h:advance(2)
check(root.writes==writes,"idle refresh repeatedly forced visibility")
s:showNative(root)
check(not root:IsShown(),"native Show escaped suppression")
local unrelated=s.frame(true)
h.env.GameTooltip.owner=unrelated;h.env.GameTooltip.shown=true
h:refresh()
check(h.env.GameTooltip.shown,"suppression hid an unrelated tooltip")
for i=1,5 do
    h.env.XenQuestDB.hideBlizzard=false;h:refresh()
    check(root:IsShown() and s.roots.WatchFrame:IsShown(),"toggle failed to restore native trackers")
    check(not s.roots.QuestWatchFrame:IsShown(),"originally hidden tracker was incorrectly shown")
    check(root.child:IsVisible() and root.mouse,"restored tracker cannot receive normal input")
    h.env.XenQuestDB.hideBlizzard=true;h:refresh()
    check(not root:IsShown(),"repeated toggle failed")
end
check(#root.hooks.OnShow==1,"OnShow hooks accumulated")
root.alpha=0.2;root.mouse=false
h.env.XenQuestDB.hideBlizzard=false;h:refresh()
check(root.alpha==0.6 and root.mouse,"saved alpha/mouse state not restored")
h.env.XenQuestDB.hideBlizzard=true;h:refresh()
local replacement=s.frame(true)
h.env.QuestWatchFrame=replacement
h:event("ADDON_LOADED","LateNativeTracker")
check(not replacement:IsShown(),"late/replaced native tracker not discovered")
s:combatChange(true)
s:showNative(root)
check(not root:IsShown(),"unprotected tracker escaped during combat")
s:showNative(s.roots.WatchFrame)
check(s.roots.WatchFrame:IsShown(),"protected tracker must defer unsafe combat mutation")
h.env.XenQuestDB.hideBlizzard=false;h:refresh()
check(not root:IsShown(),"restoration ran during combat")
h.env.XenQuestDB.hideBlizzard=true;h:refresh()
s:combatChange(false)
check(not s.roots.WatchFrame:IsShown(),"latest suppression request was not applied after combat")
h.env.ObjectiveTrackerFrame=s.frame(true)
h.env.ObjectiveTrackerFrame.forbidden=true
h:refresh() -- forbidden methods raise if touched
check(h.env.ObjectiveTrackerFrame:IsShown(),"forbidden frame was mutated")
h:event("PLAYER_LOGOUT")
check(root:IsShown() and s.roots.WatchFrame:IsShown() and replacement:IsShown(),"cleanup did not restore owned state")
check(h.env.XenQuestDB.hideBlizzard,"cleanup changed saved preference")
h:advance(1)
check(root:IsShown(),"cleanup hooks reactivated suppression")

local combat,cs=fixture(false,{combat=true})
check(cs.roots.WatchFrame:IsShown(),"protected startup changed during combat")
cs:combatChange(false)
check(not cs.roots.WatchFrame:IsShown(),"protected startup did not recover after combat")

for _,modern in ipairs({false,true}) do
    local nav,n=fixture(modern)
    local row=nav:row(102) -- completed and sorted below quests with later log indices
    check(row.titleButton:GetWidth()==row.head:GetWidth(),"title hit region overlaps item or marker area")
    table.insert(nav.log,1,harness.quest(104)) -- no render: captured index is stale
    n.badIndex=2 -- deliberately stale native lookup; row 2 is quest 101
    click(row)
    check(n.selectedID==102 and n.details==1 and n.opens==1,"title selected the wrong quest after log reorder")
    click(row)
    check(n.opens==1 and nav.env.QuestLogFrame:IsShown(),"clicking an open log toggled it closed")
    nav.env.QuestLogFrame:Hide()
    n.onOpen=function() table.insert(nav.log,1,harness.quest(105)) end
    click(row)
    check(n.selectedID==102,"OnShow index changes selected an unrelated quest")
    n.onOpen=nil
    local selections=n.selections
    n.shift=true
    click(row)
    check(n.chatLink and n.chatLink:find("quest:102:") and n.selections==selections,"shift-click used stale index or opened log")
    n.idLinks=true;n.chatLink=nil
    click(row)
    check(n.chatLink and n.chatLink:find("quest:102:"),"ID-based quest-link fallback failed")
    n.shift=false
    click(row,"RightButton");nav:refresh()
    check(row.objectives[1].shown and n.selections==selections,"right-click did not preserve collapse behavior")
    row.bubble.scripts.OnClick(row.bubble);nav:refresh()
    check(nav.env.GetSuperTrackedQuestID()==102 and n.selections==selections,"marker click opened quest log")
    n:combatChange(true);click(row)
    check(n.selections==selections,"title changed native UI during combat")
    n:combatChange(false)
    nav.env.InputUtil={IsGamepadUIEnabled=function() return true end}
    click(row)
    check(n.selections==selections,"controller mode took unsafe navigation path")
    nav.env.InputUtil=nil
    for i,q in ipairs(nav.log) do if q.id==102 then table.remove(nav.log,i);break end end
    click(row)
    check(n.selections==selections,"removed quest selected the quest occupying its former index")
    nav:refresh()

    local moving=nav:row(101)
    moving.titleButton.scripts.OnMouseDown(moving.titleButton)
    for _,q in ipairs(nav.log) do if q.id==101 then q.complete=true end end
    nav:refresh()
    check(not moving.titleButton.mouse and moving.bubble.mouse,"movement did not isolate title hit testing")
    moving.titleButton.scripts.OnClick(moving.titleButton,"LeftButton")
    check(n.selections==selections,"mouse-down before animation caused accidental selection")
    nav:settled()
    check(moving.titleButton.mouse,"title did not become interactive after animation")
    click(moving)
    check(n.selectedID==101,"settled completed title did not navigate")
    moving.quest.title=string.rep("Wrapped quest title ",12)
    for _,q in ipairs(nav.log) do if q.id==101 then q.title=moving.quest.title end end
    nav:refresh();nav:settled()
    check(moving.titleButton:GetHeight()>17,"wrapped title hit region was not resized")
end

local map,m=fixture(true,{map=true})
click(map:row(102))
check(m.selectedID==102 and m.opens==1,"ID-based map quest details navigation failed")
local unsupported,u=fixture(true,{unsupported=true})
click(unsupported:row(101))
check(u.opens==0 and #u.messages>1,"unsupported navigation did not fail gracefully")
local toggle,t=fixture(false)
toggle.env.ShowUIPanel=nil
toggle.env.ToggleQuestLog=function() t.opens=t.opens+1;toggle.env.QuestLogFrame:Show() end
click(toggle:row(101));click(toggle:row(101))
check(t.opens==1 and t.selectedID==101,"legacy ToggleQuestLog fallback closed the log")
local legacy,l=fixture(false)
legacy.env.SelectQuestLogEntry=legacy.env.QuestLog_SetSelection
legacy.env.QuestLog_SetSelection=nil
click(legacy:row(103))
check(l.selectedID==103,"SelectQuestLogEntry fallback failed")
local function readIndex(index)
    local q=legacy.log[index]
    if q then return q.title,q.level,false,q.id end
end
local native=legacy.addon.BlizzardUI
local indexOnly={title="Unique title",level=10,index=2}
legacy.log[2].title=indexOnly.title
check(native:ResolveQuest(indexOnly,readIndex)==2,"unique index-only quest failed")
legacy.log[1].title=indexOnly.title
check(native:ResolveQuest(indexOnly,readIndex)==nil,"ambiguous index-only quest was selected")
legacy.log[2].title="Another title"
check(native:ResolveQuest(indexOnly,readIndex)==nil,"moved index-only quest was guessed")
print("PASS: "..checks.." native tracker/navigation checks (mock UI)")
