local _,addon=...
local Items=addon.QuestItems
local Buttons={}
addon.QuestItemButtons=Buttons
local slots={}
local secureUnavailable=false
local viewport
local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end
local function leave(owner)
    local slot=owner.slot or owner
    slot.highlight:Hide()
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function tooltip(owner)
    local slot=owner.slot or owner
    if not slot.item or not GameTooltip then return end
    slot.highlight:Show()
    GameTooltip:SetOwner(owner,"ANCHOR_LEFT")
    if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:"..slot.item.id) end
    local instruction="Click to use quest item"
    if inCombat() then instruction="Quest quick-use is unavailable during combat."
    elseif Buttons.pending then instruction="Updating quest item availability."
    elseif not slot.action then instruction="Secure quest quick-use is unavailable on this client."
    elseif slot.item.locked then instruction="Item is temporarily locked."
    elseif not slot.item.usable then instruction="This item cannot be used here yet." end
    if GameTooltip.AddLine then GameTooltip:AddLine(instruction,0.65,0.85,0.70,true) end
    GameTooltip:Show()
end
local function mouseWheel(_,delta)
    local handler=viewport and viewport:GetScript("OnMouseWheel")
    if handler then handler(viewport,delta) end
end
local function hideAction(slot,clear)
    local action=slot.action
    if not action or inCombat() then return end
    if action:IsShown() then action:Hide();leave(action) end
    if clear and action.itemID then
        action:SetAttribute("type1",nil)
        action:SetAttribute("item1",nil)
        action.itemID,action.questKey=nil,nil
    end
end
local function createAction(slot)
    if inCombat() or secureUnavailable then return end
    if type(RegisterStateDriver)~="function" or type(SecureActionButton_OnClick)~="function" then
        secureUnavailable=true
        return
    end
    -- Never parent or anchor a protected frame to a quest row: that would also
    -- protect the row/scroll/tracker and prevent their combat-time animations.
    local ok,action=pcall(CreateFrame,"Button",nil,UIParent,"SecureActionButtonTemplate,SecureHandlerStateTemplate")
    if not ok or not action then secureUnavailable=true;return end
    action:Hide()
    if not action:GetScript("OnClick") or not action:GetScript("OnAttributeChanged") then
        secureUnavailable=true
        return
    end
    local configured=pcall(function()
        action:RegisterForClicks("LeftButtonUp","LeftButtonDown")
        -- A secure state change hides the hit target on combat entry. On exit it
        -- stays hidden until the latest quest, inventory and position are bound.
        action:SetAttribute("_onstate-xqcombat",'if newstate == "combat" then self:Hide() end')
        RegisterStateDriver(action,"xqcombat","[combat] combat; peace")
        action:SetFrameStrata("LOW")
    end)
    if not configured then secureUnavailable=true;return end
    action.slot=slot
    action:SetScript("OnEnter",tooltip)
    action:SetScript("OnLeave",leave)
    action:SetScript("OnHide",leave)
    action:EnableMouseWheel(true)
    action:SetScript("OnMouseWheel",mouseWheel)
    -- Keep the template's secure OnClick; no insecure handler ever uses an item.
    slot.action=action
end
local function createSlot(row,index)
    local slot=CreateFrame("Button",nil,row)
    slot.row=row
    slot:SetSize(24,24)
    slot:SetPoint("TOPRIGHT",row,"TOPRIGHT",-2-(index-1)*28,-2)
    slot.icon=slot:CreateTexture(nil,"ARTWORK")
    slot.icon:SetAllPoints(slot)
    slot.highlight=slot:CreateTexture(nil,"OVERLAY")
    slot.highlight:SetAllPoints(slot)
    slot.highlight:SetColorTexture(1,1,1,0.13)
    slot.highlight:Hide()
    slot.count=slot:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall")
    slot.count:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",0,0)
    local ok,cooldown=pcall(CreateFrame,"Cooldown",nil,slot,"CooldownFrameTemplate")
    if ok and cooldown and cooldown.SetCooldown then
        slot.cooldown=cooldown
        cooldown:SetAllPoints(slot)
        cooldown:EnableMouse(false)
    end
    slot:EnableMouse(true)
    slot:SetScript("OnEnter",tooltip)
    slot:SetScript("OnLeave",leave)
    slot:EnableMouseWheel(true)
    slot:SetScript("OnMouseWheel",mouseWheel)
    slot:SetScript("OnClick",function() end) -- absorb clicks when action is disabled
    slot:SetScript("OnHide",function(self) hideAction(self,true);leave(self) end)
    row.itemSlots=row.itemSlots or {}
    row.itemSlots[index]=slot
    slots[#slots+1]=slot
    return slot
end
function Buttons:Release(row)
    for _,slot in ipairs(row.itemSlots or {}) do
        hideAction(slot,true)
        slot.item=nil
        slot:Hide()
    end
end
function Buttons:UpdateRow(row,q,enabled)
    local items=enabled and q.items or {}
    for index,item in ipairs(items or {}) do
        local slot=row.itemSlots and row.itemSlots[index] or createSlot(row,index)
        if not slot.item or slot.item.id~=item.id or slot.item.questKey~=item.questKey then
            hideAction(slot,true)
            leave(slot)
        end
        slot.item=item
        slot.icon:SetTexture(item.icon)
        local dim=inCombat() or item.locked or not item.usable
        slot.icon:SetVertexColor(dim and 0.5 or 1,dim and 0.5 or 1,dim and 0.5 or 1)
        slot.count:SetText(item.count>1 and tostring(item.count) or "")
        if slot.cooldown then
            local start,duration,on=Items:Cooldown(item)
            if type(start)=="number" and type(duration)=="number" and duration>0 and on~=0 and on~=false then
                slot.cooldown:SetCooldown(start,duration)
                slot.cooldown:Show()
            else slot.cooldown:Hide() end
        end
        slot:Show()
    end
    for index=#(items or {})+1,#(row.itemSlots or {}) do
        local slot=row.itemSlots[index]
        hideAction(slot,true)
        slot.item=nil
        slot:Hide()
    end
    return #(items or {})*28
end
function Buttons:HideActions()
    for _,slot in ipairs(slots) do hideAction(slot,true) end
end
function Buttons:MaskRow(row,alpha)
    for _,slot in ipairs(row.itemSlots or {}) do
        slot:EnableMouse(alpha>0.95)
        if alpha<=0.95 then
            hideAction(slot,false)
            leave(slot)
            if slot.action then leave(slot.action) end
        end
    end
end
function Buttons:Invalidate()
    self.pending=true
    self:HideActions()
end
function Buttons:Sync(tracker,db)
    viewport=tracker.scroll
    if inCombat() or self.pending or #slots==0 then return end -- all protected mutations
    local visible=db.showQuestItems and not db.minimized and tracker:IsVisible()
    local parentScale=UIParent:GetEffectiveScale()
    local scroll=tracker.scroll
    local clipScale=scroll:GetEffectiveScale()/parentScale
    local left,right,top,bottom=scroll:GetLeft(),scroll:GetRight(),scroll:GetTop(),scroll:GetBottom()
    for _,slot in ipairs(slots) do
        local item=slot.item
        local row=slot.row
        local shown=visible and item and slot:IsVisible() and (row.paintAlpha or 1)>0.95 and not item.locked
        local x,y,scale,size
        if shown then
            scale=slot:GetEffectiveScale()/parentScale
            x,y=slot:GetLeft(),slot:GetTop()
            size=24*scale
            if x and y and left and right and top and bottom then
                x,y=x*scale,y*scale
                -- Only fully visible icons get a hit target; never click outside
                -- the scroll viewport, including during a bounce or while dragging.
                shown=x>=left*clipScale and x+size<=right*clipScale and y<=top*clipScale and y-size>=bottom*clipScale
            else shown=false end
        end
        if shown then
            if not slot.action then createAction(slot) end
            local action=slot.action
            if action then
                if action.itemID~=item.id or action.questKey~=item.questKey then
                    hideAction(slot,true)
                    action:SetAttribute("item1","item:"..item.id)
                    action:SetAttribute("type1","item")
                    action.itemID,action.questKey=item.id,item.questKey
                end
                if action.x~=x or action.y~=y or action.size~=size then
                    action:ClearAllPoints()
                    action:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
                    action:SetSize(size,size)
                    action.x,action.y,action.size=x,y,size
                end
                local level=row:GetFrameLevel()+5
                if action.level~=level then action:SetFrameLevel(level);action.level=level end
                if not action:IsShown() then action:Show() end
            end
        else hideAction(slot,true) end
    end
end
