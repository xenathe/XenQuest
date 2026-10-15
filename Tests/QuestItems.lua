-- Lua 5.1; run from the addon directory. Synthetic IDs here are test fixtures,
-- never shipped quest mappings. These mocks cannot certify WoW's secure runtime.
local harness=assert(loadfile("Tests/Completion.lua"))("harness")
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function fixture(modern,options)
    options=options or {}
    local log={harness.quest(901),harness.quest(902),harness.quest(903)}
    local state={combat=options.combat or false,scans=0,uses=0,drivers={},
        bag={{id=1001,count=2},{id=1002,count=1},{id=1003,count=1},{id=1004,count=1}},
        items={[1001]={icon=111,spell="Use first",cooldown={12,30,1}},
            [1002]={icon=222,spell="Use second"},[1003]={icon=333},[1004]={icon=444,spell="Use fourth"}},
        special={[901]={1001},[902]={1002}}}
    local h=harness.boot(log,modern,{showQuestItems=not options.disabled},function(env,objects,methods)
        env.InCombatLockdown=function() return state.combat end
        function methods:GetEffectiveScale()
            return (self.scale or 1)*(self.parent and self.parent:GetEffectiveScale() or 1)
        end
        local width,height=methods.GetWidth,methods.GetHeight
        function methods:GetWidth()
            if self.kind=="ScrollFrame" then return self.parent.width-21 end
            return width(self)
        end
        function methods:GetHeight()
            if self.kind=="ScrollFrame" then return self.parent.height-53 end
            return height(self)
        end
        function methods:GetLeft()
            local tracker=env.XenQuestTracker
            if self==env.UIParent then return 0 end
            if self==tracker then return 100+(self.dragX or 0) end
            if self.kind=="ScrollFrame" then return self.parent:GetLeft()+9 end
            if tracker and self==tracker.content then return tracker.scroll:GetLeft() end
            if self.row then return self.row:GetLeft()+self.row:GetWidth()+self.point[4]-self.width end
            if self.head then return self.parent:GetLeft()+5+(self.x or 0) end
            return self.parent and self.parent:GetLeft() or 0
        end
        function methods:GetTop()
            local tracker=env.XenQuestTracker
            if self==env.UIParent then return 1080 end
            if self==tracker then return 900 end
            if self.kind=="ScrollFrame" then return self.parent:GetTop()-43 end
            if tracker and self==tracker.content then return tracker.scroll:GetTop()+tracker.scroll:GetVerticalScroll() end
            if self.row then return self.row:GetTop()+self.point[5] end
            if self.head then return self.parent:GetTop()-(self.y or 0) end
            return self.parent and self.parent:GetTop() or 0
        end
        function methods:GetRight() return self:GetLeft()+self:GetWidth() end
        function methods:GetBottom() return self:GetTop()-self:GetHeight() end
        function methods:GetFrameLevel() return self.level or 5 end
        function methods:SetFrameLevel(level) self.level=level end
        function methods:SetCooldown(start,duration) self.cooldownValues={start,duration} end
        function methods:SetTexture(texture) self.texture=texture end
        function methods:SetAttribute(name,value)
            self.attributes=self.attributes or {}
            self.attributes[name]=value
            if name=="state-xqcombat" then
                local chunk=assert(loadstring("return function(self,newstate) "..self.attributes["_onstate-xqcombat"].." end"))
                chunk()(self,value)
            end
        end
        -- Any addon-driven protected write during combat is a hard test failure.
        for _,name in ipairs({"SetAttribute","SetPoint","ClearAllPoints","SetSize","SetScale",
            "SetFrameLevel","SetFrameStrata","Show","Hide","RegisterForClicks","EnableMouse"}) do
            local original=methods[name]
            methods[name]=function(self,...)
                assert(not (self.secure and state.combat and not state.secureContext),"protected write in combat: "..name)
                if self.secure and name=="SetPoint" then
                    assert(select(2,...)==env.UIParent,"secure frame anchored to an animated row")
                end
                return original(self,...)
            end
        end
        if not options.noSecure then
            env.SecureActionButton_OnClick=function(button)
                assert(state.hardwareClick,"addon invoked item action without a hardware click")
                assert(button:IsShown() and not state.combat,"inactive action clicked")
                assert(button.attributes.type1=="item","not a secure item action")
                assert(not button.attributes.unit and not button.attributes.macrotext,"automatic targeting/macro")
                state.uses=state.uses+1
                state.used=button.attributes.item1
            end
            env.RegisterStateDriver=function(button,name,condition)
                assert(not state.combat,"state driver registered in combat")
                check(name=="xqcombat" and condition=="[combat] combat; peace","unexpected combat driver")
                state.drivers[#state.drivers+1]=button
                button:SetAttribute("state-xqcombat","peace")
            end
        end
        local create=env.CreateFrame
        env.CreateFrame=function(kind,name,parent,template)
            local secure=template and template:find("SecureActionButtonTemplate",1,true)
            if secure then
                assert(not state.combat,"protected frame created in combat")
                if options.badTemplate then error("template unavailable") end
                assert(parent==env.UIParent,"protected child would protect the tracker")
            end
            if kind=="Cooldown" and options.noCooldown then error("cooldown template unavailable") end
            local frame=create(kind,name,parent)
            if secure then
                frame.secure=true
                frame.scripts.OnClick=env.SecureActionButton_OnClick
                frame.scripts.OnAttributeChanged=function() end
            end
            return frame
        end
        env.GameTooltip={}
        function env.GameTooltip:SetOwner(owner) self.owner=owner end
        function env.GameTooltip:IsOwned(owner) return self.owner==owner end
        function env.GameTooltip:SetHyperlink(link) self.link=link end
        function env.GameTooltip:AddLine(text) self.instruction=text end
        function env.GameTooltip:SetText(text) self.text=text end
        function env.GameTooltip:Show() self.shown=true end
        function env.GameTooltip:Hide() self.shown=false end
        -- Forbidden insecure entry points deliberately fail, even out of combat.
        env.UseItemByName=function() error("insecure item use") end
        env.UseContainerItem=env.UseItemByName
        local function count(id)
            local n=0
            for _,item in ipairs(state.bag) do if item.id==id then n=n+item.count end end
            return n
        end
        local function slots(bag)
            state.scans=state.scans+1
            return bag==0 and #state.bag or 0
        end
        local function info(bag,slot)
            local item=state.bag[slot]
            local metadata=state.items[item.id]
            if modern then return {itemID=item.id,iconFileID=metadata.icon,stackCount=item.count,isLocked=item.locked,hyperlink="item:"..item.id} end
            return metadata.icon,item.count,item.locked,nil,nil,nil,"item:"..item.id,nil,nil,item.id
        end
        local function questInfo(bag,slot)
            local item=state.bag[slot]
            if modern then return {isQuestItem=true,questID=item.questID} end
            return true,item.questID,false
        end
        local function spell(id) return state.items[id] and state.items[id].spell end
        local function icon(id) return state.items[id] and state.items[id].icon end
        local function cooldown(id) return unpack(state.items[id].cooldown or {0,0,1}) end
        if not options.noItems then
            if modern then
                env.C_Container={GetContainerNumSlots=slots,GetContainerItemInfo=info,GetContainerItemQuestInfo=questInfo,GetItemCooldown=cooldown}
                env.C_Item={GetItemSpell=spell,GetItemCount=count,GetItemIconByID=icon,IsUsableItem=function() return true end}
            else
                env.GetContainerNumSlots,env.GetContainerItemInfo,env.GetContainerItemQuestInfo=slots,info,questInfo
                env.GetItemSpell,env.GetItemCount,env.GetItemIcon,env.GetItemCooldown=spell,count,icon,cooldown
            end
            env.GetQuestLogSpecialItemInfo=function(index)
                assert(log[index],"special-item API received a quest ID instead of a log index")
                local special=state.special[log[index].id]
                if special then return "item:"..special[1],icon(special[1]),count(special[1]),special.showWhenComplete end
            end
        end
    end)
    function state:combatChange(combat)
        self.combat=combat
        self.secureContext=true
        for _,button in ipairs(self.drivers) do button:SetAttribute("state-xqcombat",combat and "combat" or "peace") end
        self.secureContext=false
        h:event(combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    function state:bagChanged() h:event("BAG_UPDATE",0);h:advance(0.36) end
    return h,state
end

for _,modern in ipairs({false,true}) do
    local h,s=fixture(modern)
    local first,second=h:row(901),h:row(902)
    local slot=first.itemSlots[1]
    check(slot.icon.texture==111 and slot:GetWidth()==24,"actual item icon and size")
    check(slot.count.textValue=="2" and slot.cooldown.shown,"stack count and cooldown")
    check(slot.action and slot.action:IsShown(),"owned special item lacks secure action")
    check(slot.action.attributes.item1=="item:1001" and slot.action.questKey=="quest:901","wrong secure binding")
    check(first.head:GetWidth()==first:GetWidth()-60,"title does not reserve icon width")
    check(not h:row(903).itemSlots,"unrelated quest got a bag item")
    local scans=s.scans
    h:advance(2)
    check(s.scans==scans,"idle polling rescanned bags")
    h:event("BAG_UPDATE_COOLDOWN");h:advance(0.36)
    check(s.scans==scans,"cooldown update rescanned bags")
    s.items[1001].cooldown={0,0,1}
    h:event("SPELL_UPDATE_COOLDOWN");h:advance(0.36)
    check(not slot.cooldown.shown,"cooldown overlay was not cleared")
    slot.action.scripts.OnEnter(slot.action)
    check(h.env.GameTooltip.link=="item:1001" and h.env.GameTooltip.instruction=="Click to use quest item","normal item tooltip")
    s.hardwareClick=true
    slot.action.scripts.OnClick(slot.action)
    s.hardwareClick=false
    check(s.uses==1 and s.used=="item:1001" and h.env.XenQuestDB.primaryQuest==0,"item click leaked into parent quest click")
    first.scripts.OnClick(first,"RightButton");h:refresh()
    check(slot:IsShown() and slot.action:IsShown(),"manual collapse hid quick-use icon")
    s.bag[1].locked=true;s:bagChanged()
    check(not slot.action:IsShown(),"locked item action remained active")
    s.bag[1].locked=false;s:bagChanged()
    check(slot.action:IsShown(),"unlock did not restore item action")
    h.env.XenQuestTracker:SetScale(1.5)
    h.env.XenQuestTracker.dragX=50
    h.env.XenQuestDB.width=400
    h.env.XenQuestTracker:SetWidth(400)
    h:refresh()
    check(slot.action.size==36 and slot.action.x==slot:GetLeft()*1.5,"scaled/dragged secure target detached from icon")
    h.env.XenQuestTracker.scroll:SetVerticalScroll(10);h:tick(0.01)
    check(not slot.action:IsShown(),"partially clipped icon has an external hit target")
    h.env.XenQuestTracker.scroll:SetVerticalScroll(0);h:tick(0.01)
    check(slot.action:IsShown(),"scroll back did not restore hit target")
    h.env.XenQuestTracker:SetHeight(100)
    slot.action.scripts.OnMouseWheel(slot.action,-1)
    check(h.env.XenQuestTracker.scroll:GetVerticalScroll()>0,"wheel over secure item target did not scroll tracker")
    h.env.XenQuestTracker:SetHeight(430)
    h.env.XenQuestTracker.scroll:SetVerticalScroll(0);h:tick(0.01)

    s:combatChange(true)
    check(not slot.action:IsShown(),"secure driver did not hide action on combat entry")
    slot.scripts.OnEnter(slot)
    check(h.env.GameTooltip.instruction:find("combat"),"combat tooltip missing")
    h.log[1].complete=true;h:refresh()
    check(first.quest.state.animation and not slot:IsShown(),"completion integration in combat")
    table.remove(h.log,2);h:refresh()
    check(not second:IsShown(),"removing a quest in combat failed")
    h.env.SlashCmdList.XENQUEST("hide");h:tick(0.01)
    h.env.SlashCmdList.XENQUEST("show");h:tick(0.01)
    h.env.XenQuestTracker.collapse.scripts.OnClick()
    h.env.XenQuestTracker.collapse.scripts.OnClick()
    s:combatChange(false)
    h:tick(0.01)
    check(not slot.action:IsShown(),"combat exit exposed a stale binding before refresh")
    h:settled()
    check(not slot:IsShown() and not slot.action:IsShown(),"completed quest left a floating action")
    check(s.uses==1,"updates automatically used an item")

    local a,b=fixture(modern)
    b.bag[2].questID=901 -- native association outranks the special item
    b.bag[3].questID=901 -- ordinary quest item with no use spell: ignore
    b:bagChanged()
    local row=a:row(901)
    check(#row.quest.items==2 and row.quest.items[1].id==1002 and row.quest.items[2].id==1001,"association priority/dedup/usability")
    check(row.head:GetWidth()==row:GetWidth()-88,"two icons overlap title")
    b.bag[4].questID=901;b:bagChanged()
    check(#row.quest.items==2 and row.quest.items[2].id==1004,"two-icon cap and deterministic ordering")
    table.remove(b.bag,2);a:event("BAG_UPDATE",0)
    check(not row.itemSlots[1].action:IsShown(),"inventory event did not suspend old action immediately")
    a:tick(0.01)
    check(not row.itemSlots[1].action:IsShown(),"old inventory rebound before refreshed data")
    a:advance(0.36)
    check(row.itemSlots[1].action.itemID==1004,"slot reuse retained the wrong item")
    b.bag={};b:bagChanged()
    check(#row.quest.items==0 and not row.itemSlots[1]:IsShown(),"missing item icon not removed")

    local keep,k=fixture(modern)
    k.special[901].showWhenComplete=true
    keep.log[1].complete=true;keep:refresh()
    check(keep:row(901).itemSlots[1]:IsShown(),"native showWhenComplete exception ignored")
    keep:settled()
    check(keep:row(901).itemSlots[1].action.questKey=="quest:901","sorting reassigned the secure action")
    local button=keep:row(901).itemSlots[1].action
    keep.env.XenQuestTracker.collapse.scripts.OnClick()
    check(not button:IsShown(),"tracker collapse left a floating action")
    keep.env.XenQuestTracker.collapse.scripts.OnClick();keep:refresh()
    check(button:IsShown(),"tracker expansion did not restore action")
    local numObjects=#keep.objects
    for i=1,5 do
        table.remove(keep.log,1);keep:refresh()
        table.insert(keep.log,1,harness.quest(901));keep:refresh()
    end
    check(#keep.objects==numObjects,"secure buttons accumulated during row reuse")
    for _,o in ipairs(keep.objects) do
        if o.secure and o:IsShown() then
            check(o.slot.item and o.questKey==o.slot.item.questKey and o.itemID==o.slot.item.id,"stale visible secure binding")
        end
    end
end

local disabled,d=fixture(true,{disabled=true})
check(d.scans==0 and not disabled:row(901).itemSlots,"saved disabled setting ignored")
for _,o in ipairs(disabled.objects) do
    if o.text and o.text.textValue and o.text.textValue:find("Show quest item buttons",1,true) then
        o.scripts.OnClick(o);disabled:refresh()
        check(disabled:row(901).itemSlots[1].action:IsShown(),"setting did not enable icons")
        o.scripts.OnClick(o);disabled:refresh()
        check(not disabled:row(901).itemSlots[1]:IsShown(),"setting did not hide icons")
    end
end
for _,options in ipairs({{noSecure=true},{badTemplate=true},{noCooldown=true},{noItems=true},{combat=true}}) do
    local h,s=fixture(true,options)
    if options.noItems then check(not h:row(901).itemSlots,"missing APIs invented an item")
    else
        local slot=h:row(901).itemSlots[1]
        check(slot~=nil,"unsupported quick-use hid informative icon")
        if options.noSecure or options.badTemplate or options.combat then
            check(not slot.action,"unsupported/combat secure button created")
            slot.scripts.OnEnter(slot)
            check(h.env.GameTooltip.instruction:find("unavailable"),"disabled icon lacks informative tooltip")
        end
        if options.combat then
            s:combatChange(false);h:refresh()
            check(slot.action and slot.action:IsShown(),"combat startup did not recover")
        end
    end
end
local curated,c=fixture(true)
curated.addon.QuestItems.Verified[903]={1004} -- synthetic, explicitly test-only mapping
curated:refresh()
check(curated:row(903).itemSlots[1].item.id==1004,"verified mapping extension failed")
check(next(curated.addon.QuestItems.Verified)==903,"unverified production mappings were enabled")

local late,l=fixture(true)
l.items[1001].icon=nil;l:bagChanged()
check(not late:row(901).itemSlots[1]:IsShown(),"uncached icon was replaced with an unrelated image")
l.items[1001].icon=111
late:event("GET_ITEM_INFO_RECEIVED",1001);late:advance(0.36)
check(late:row(901).itemSlots[1].icon.texture==111 and late:row(901).itemSlots[1].action:IsShown(),"item-data event did not restore icon")
late.env.C_Container=nil;l:bagChanged()
check(late:row(901).itemSlots[1].action:IsShown(),"native ownership fallback needs bag APIs unnecessarily")
l.special[901]={1003};l:bagChanged()
check(late:row(901).itemSlots[1].item.id==1003,"native special-item evidence was incorrectly rejected")
print("PASS: "..checks.." quest-item checks (mock secure runtime, legacy and namespaced APIs)")
