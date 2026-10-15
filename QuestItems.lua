-- Quest/item detection, independent of row layout and protected click targets.
local _,addon=...
local Items={Verified={}}
addon.QuestItems=Items

-- Extend Verified as [questID]={itemID,...}, using only usable items confirmed
-- in the target client. Record the client build and verification source here.
-- Candidate, NOT enabled: Crown of the Earth (921) / Crystal Phial (5185).
-- Installed QuestieDB_Forever.toc 1.0.6, X-Quest-921-S field 11 = 5185 and
-- X-Item-5185-S field 1 = Crystal Phial, corroborate the IDs. The local client's
-- questcache has no 921 record, so this is not yet direct client verification.
-- Native associations/special-item APIs work without any database entries.

local inventory,associations={},{}
local bagDirty=true
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c,d,e,f,g,h,i,j=pcall(fn,...)
    if ok then return a,b,c,d,e,f,g,h,i,j end
end
local function api(namespace,name,legacy)
    return namespace and namespace[name] or _G[legacy or name]
end
local function itemID(link)
    return type(link)=="string" and tonumber(link:match("item:(%d+)")) or nil
end
local function scanBags()
    inventory,associations={},{}
    -- Only carried bags, never bank bags. A legacy keyring may contain quest tools.
    local bags={0}
    for bag=1,(NUM_BAG_SLOTS or 4) do bags[#bags+1]=bag end
    if KEYRING_CONTAINER then bags[#bags+1]=KEYRING_CONTAINER end
    for _,bag in ipairs(bags) do
        local n=call(api(C_Container,"GetContainerNumSlots"),bag) or 0
        for slot=1,n do
            local icon,count,locked,_,_,_,link,_,_,id=call(api(C_Container,"GetContainerItemInfo"),bag,slot)
            if type(icon)=="table" then
                local info=icon
                icon,count,locked,link,id=info.iconFileID,info.stackCount,info.isLocked,info.hyperlink,info.itemID
            end
            id=id or itemID(link) or call(api(C_Container,"GetContainerItemID"),bag,slot)
            if type(id)=="number" and id>0 then
                local entry=inventory[id]
                if not entry then
                    entry={id=id,icon=icon,link=link,count=0,bag=bag,slot=slot,locked=locked==true}
                    inventory[id]=entry
                end
                entry.count=entry.count+(count or 1)
                if not locked then entry.locked=false;entry.bag=bag;entry.slot=slot end
                local info,questID=call(api(C_Container,"GetContainerItemQuestInfo"),bag,slot)
                if type(info)=="table" then questID=info.questID end
                -- The quest-item flag by itself proves neither identity nor usability.
                if type(questID)=="number" and questID>0 then
                    associations[questID]=associations[questID] or {}
                    associations[questID][id]=true
                end
            end
        end
    end
    bagDirty=false
end
function Items:Invalidate(event)
    if event~="BAG_UPDATE_COOLDOWN" and event~="SPELL_UPDATE_COOLDOWN" then bagDirty=true end
end
function Items:Refresh()
    if bagDirty then scanBags() end
end
function Items:ForQuest(q)
    local result,seen={},{}
    local function add(id,source,icon,charges,showWhenComplete)
        if type(id)~="number" or id<=0 or seen[id] or #result>=2 then return end
        if q.complete and not showWhenComplete then return end
        local bag=inventory[id]
        local count=bag and bag.count or call(api(C_Item,"GetItemCount"),id,false,false)
        if type(count)~="number" or count<=0 then return end
        if source=="association" then
            -- A use spell is positive evidence; an item class or name is not.
            local name,spell=call(api(C_Item,"GetItemSpell"),id)
            if not name and not spell then
                call(api(C_Item,"GetItemInfo"),id) -- request uncached information
                return
            end
        end
        icon=(bag and bag.icon) or icon or call(api(C_Item,"GetItemIconByID","GetItemIcon"),id)
        if not icon then icon=select(10,call(api(C_Item,"GetItemInfo"),id)) end
        if not icon then return end -- Never substitute an unrelated icon.
        local uses=charges or call(api(C_Item,"GetItemCount"),id,false,true)
        local usable=call(api(C_Item,"IsUsableItem"),id)
        result[#result+1]={id=id,questKey=q.key,source=source,icon=icon,
            count=type(uses)=="number" and uses>0 and uses or count,
            locked=bag and bag.locked,usable=usable~=false,
            bag=bag and bag.bag,slot=bag and bag.slot,index=q.index}
        seen[id]=true
    end
    if q.id and not q.complete then
        local ids={}
        for id in pairs(associations[q.id] or {}) do ids[#ids+1]=id end
        table.sort(ids) -- deterministic order when more than one bag item is associated
        for _,id in ipairs(ids) do add(id,"association") end
    end
    -- This API takes a current LOG INDEX, never a quest ID.
    local link,icon,charges,showWhenComplete=call(GetQuestLogSpecialItemInfo,q.index)
    add(itemID(link),"special",icon,charges,showWhenComplete==true or showWhenComplete==1)
    for _,id in ipairs(q.id and self.Verified[q.id] or {}) do add(id,"database") end
    return result
end
function Items:Cooldown(item)
    local start,duration,enabled=call(api(C_Container,"GetItemCooldown"),item.id)
    if start==nil and item.bag then
        start,duration,enabled=call(api(C_Container,"GetContainerItemCooldown"),item.bag,item.slot)
    end
    if start==nil and item.source=="special" then
        start,duration,enabled=call(GetQuestLogSpecialItemCooldown,item.index)
    end
    return start,duration,enabled
end
