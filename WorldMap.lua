-- XenQuest: World Map Integration (experimental, WoW Forever).
-- Read-only quest locations come from the game's map API. Nothing is guessed.
-- Avoids modifications to the Blizzard WorldMapFrame, scroll handlers or pins.
local _, addon = ...
local WorldMap = {}
addon.WorldMap = WorldMap

local db, mapFrame, canvas
local ticker = CreateFrame("Frame", "XenQuestWorldMapWatcher")
local pins = {}
local lastMapID, lastCanvas, lastDataStamp
local attachedKind="none"
local lastReason="Map has not been opened"
local lastLocationCount=0
local lastQuestCount=0
local accumulated = 0
local MAX_PINS = 80
local normalSize, focusedSize = 22, 27

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function activeQuests()
    -- On older clients quest details can be indexed with legacy helpers.
    -- Require positively confirmed quest-log membership before showing a pin.
    local total = call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    if type(total) ~= "number" then total = call(GetNumQuestLogEntries) end
    if type(total) ~= "number" then return nil end
    local quests = {}
    for index=1,math.min(600,total) do
        local id, complete, title, isHeader
        local info = call(C_QuestLog and C_QuestLog.GetInfo, index)
        if type(info) == "table" then
            id = info.questID
            title = info.title
            complete = info.isComplete == true or info.isComplete == 1
            isHeader = info.isHeader
        elseif type(GetQuestLogTitle) == "function" then
            local name,_,_,header,_,done,_,questID = call(GetQuestLogTitle,index)
            id,title,isHeader = questID,name,header
            complete = done == 1 or done == true
        end
        if not isHeader and type(id)=="number" and id>0 then
            quests[id] = {id=id, title=title, complete=complete}
        end
    end
    return quests
end

-- Forever's classic-style Map & Quest Log uses WorldMapDetailFrame /
-- WorldMapButton and does not expose the newer MapCanvasMixin API.
-- Prefer the map actually being viewed, never the player's zone unless the
-- client has no viewed-map identifier at all.
local function currentMapID()
    if not mapFrame then return nil end
    local id=call(mapFrame.GetMapID,mapFrame)
    if type(id)~="number" or id<=0 then id=mapFrame.mapID end
    if type(id)~="number" or id<=0 then
        id=call(GetCurrentMapAreaID) -- classic world-map's currently displayed zone
    end
    if type(id)=="number" and id>0 then return id end
    -- Last resort on clients that expose C_Map but no map-frame map ID.
    -- These clients may show fewer pins when browsing outside the player zone.
    id=call(C_Map and C_Map.GetBestMapForUnit,"player")
    if type(id)=="number" and id>0 then return id end
end

local function validXY(x,y)
    return type(x)=="number" and type(y)=="number"
        and x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1
end

local function getQuestLocations(mapID, active)
    local locations, seen = {}, {}
    if not active or not C_QuestLog then return locations end
    -- Coordinates returned by GetQuestsOnMap(mapID) are expressed in mapID
    -- space, even when the POI also has its own related mapID field.
    local poiList = call(C_QuestLog.GetQuestsOnMap, mapID)
    if type(poiList) == "table" then
        for _,poi in pairs(poiList) do
            if type(poi)=="table" and type(poi.questID)=="number"
                and active[poi.questID] and not poi.isQuestStart
                and validXY(poi.x,poi.y) and not seen[poi.questID] then
                local questID=poi.questID
                locations[#locations+1] = {
                    id=questID, x=poi.x, y=poi.y,
                    title=active[questID].title, complete=active[questID].complete,
                }
                seen[questID]=true
            end
        end
    end
    -- Some client quests use a next-waypoint marker but no POI list entry.
    -- Only consider the requested map's coordinate space.
    for questID,quest in pairs(active) do
        if not seen[questID] then
            local x,y=call(C_QuestLog.GetNextWaypointForMap, questID,mapID)
            if not validXY(x,y) then
                local returnedMap,wx,wy=call(C_QuestLog.GetNextWaypoint,questID)
                if returnedMap==mapID then x,y=wx,wy end
            end
            if validXY(x,y) then
                locations[#locations+1]={
                    id=questID, x=x, y=y,
                    title=quest.title, complete=quest.complete,
                }
            end
        end
    end
    table.sort(locations, function(a,b) return a.id<b.id end)
    return locations
end

local function selectedQuestID()
    local nav=addon.Navigation
    if nav and type(nav.GetSelectedQuestID)=="function" then
        local id=call(nav.GetSelectedQuestID,nav)
        if type(id)=="number" then return id end
    end
    if C_SuperTrack and type(C_SuperTrack.GetSuperTrackedQuestID)=="function" then
        return call(C_SuperTrack.GetSuperTrackedQuestID)
    end
    return call(GetSuperTrackedQuestID)
end

local function setQuestSelection(questID)
    local nav=addon.Navigation
    local current=selectedQuestID()
    local target=(current==questID) and 0 or questID
    local fn=(C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID)
        or (type(SetSuperTrackedQuestID)=="function" and SetSuperTrackedQuestID)
    -- Same native + local selection process as the tracker marker.
    local success=true
    if type(fn)=="function" then
        local ok,result=pcall(fn,target)
        success=ok and result~=false
    end
    if success and nav and type(nav.OnQuestSelected)=="function" then
        call(nav.OnQuestSelected,nav,target)
    end
    return success
end

local function hideAll()
    for _,pin in ipairs(pins) do pin:Hide() end
end

local function createPin()
    if not canvas then return nil end
    local pin=CreateFrame("Button",nil,canvas)
    pin:SetSize(normalSize,normalSize)
    pin:SetFrameLevel((canvas:GetFrameLevel() or 0)+12)
    pin:RegisterForClicks("LeftButtonUp")
    pin:EnableMouse(true)
    local bg=pin:CreateTexture(nil,"BACKGROUND")
    bg:SetPoint("CENTER")
    bg:SetSize(17,17)
    bg:SetColorTexture(0.025,0.055,0.08,0.86)
    local icon=pin:CreateTexture(nil,"ARTWORK")
    icon:SetAllPoints(pin)
    pin.icon=icon
    local focus=pin:CreateTexture(nil,"OVERLAY")
    focus:SetPoint("BOTTOMLEFT",pin,"BOTTOMLEFT",2,1)
    focus:SetPoint("BOTTOMRIGHT",pin,"BOTTOMRIGHT",-2,1)
    focus:SetHeight(2)
    pin.focus=focus
    pin:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local questTitle=self.questTitle or ("Quest "..tostring(self.questID))
        GameTooltip:SetText(questTitle,1,0.86,0.42)
        GameTooltip:AddLine(self.isComplete and "Ready to turn in" or "Quest objective area",0.86,0.91,0.94)
        GameTooltip:AddLine("Click to navigate (click again to stop)",0.65,0.78,0.81)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pin:SetScript("OnClick",function(self)
        if self.questID and setQuestSelection(self.questID) then
            WorldMap:Refresh()
        end
    end)
    pin:Hide()
    pins[#pins+1]=pin
    return pin
end

function WorldMap:Refresh()
    if not db or not db.showMapPins then
        lastReason="Map pins are disabled in XenQuest settings"
        hideAll()
        return
    end
    if not mapFrame or not canvas or not mapFrame:IsShown() then
        lastReason="World map is closed or the map canvas is not attached"
        hideAll()
        return
    end
    local mapID=currentMapID()
    local width,height=canvas:GetWidth(),canvas:GetHeight()
    if not mapID or type(width)~="number" or type(height)~="number"
        or width<40 or height<40 then
        lastReason="Missing displayed map ID or invalid map drawing dimensions"
        hideAll()
        return
    end
    local quests=activeQuests()
    if not quests then
        lastReason="Client did not return quest-log entries"
        hideAll()
        return
    end
    lastQuestCount=0
    for _ in pairs(quests) do lastQuestCount=lastQuestCount+1 end
    local locations=getQuestLocations(mapID,quests)
    lastLocationCount=#locations
    lastReason=(#locations>0) and "Pins available" or "No valid quest positions returned for displayed map"
    local activeID=selectedQuestID()
    local isIce=(db.theme=="ice")
    local texture="Interface\\AddOns\\XenQuest\\Media\\"..(isIce and "TrackedArrowPremiumIce" or "TrackedArrowPremiumGold")
    local used=0
    for _,loc in ipairs(locations) do
        if used>=MAX_PINS then break end
        used=used+1
        local pin=pins[used] or createPin()
        if not pin then break end
        local focused=(loc.id==activeID)
        local size=focused and focusedSize or normalSize
        pin:SetSize(size,size)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER",canvas,"TOPLEFT",loc.x*width,-loc.y*height)
        pin.questID=loc.id
        pin.questTitle=loc.title or call(C_QuestLog.GetTitleForQuestID,loc.id)
        pin.isComplete=loc.complete
        pin.icon:SetTexture(texture)
        pin.focus:SetShown(focused)
        pin.focus:SetColorTexture(isIce and 0.46 or 0.96,isIce and 0.82 or 0.77,isIce and 0.98 or 0.36,1)
        pin:Show()
    end
    for index=used+1,#pins do pins[index]:Hide() end
    lastMapID=mapID
end

-- Support both the modern map canvas and Forever's classic map UI.
-- Both drawing targets scale with the world map and use normalised (x,y).
local function findMapCanvas(map)
    local container=map and map.ScrollContainer
    local child=container and (container.Child or call(container.GetScrollChild,container))
    if child then return child,"modern MapCanvas" end
    -- Classic-style Map & Quest Log (the parchment map left of quest list).
    -- The detail frame is where Blizzard positions player and quest markers.
    if WorldMapDetailFrame then return WorldMapDetailFrame,"classic WorldMapDetailFrame" end
    if WorldMapButton then return WorldMapButton,"classic WorldMapButton" end
    return nil,"unrecognised world-map layout"
end

local function attachMap()
    local map=WorldMapFrame
    if not map then
        lastReason="WorldMapFrame not loaded yet"
        return false
    end
    local child,kind=findMapCanvas(map)
    if not child then
        lastReason="No recognised map canvas (new or classic)"
        return false
    end
    if mapFrame==map and canvas==child then return true end
    mapFrame,canvas=map,child
    attachedKind=kind
    -- Keep the pooled pins attached to the actual map when the UI rebuilds.
    for _,pin in ipairs(pins) do
        pin:SetParent(canvas)
        pin:SetFrameLevel((canvas:GetFrameLevel() or 0)+12)
    end
    if map.HookScript then
        map:HookScript("OnShow",function() WorldMap:Refresh() end)
        map:HookScript("OnHide",hideAll)
    end
    lastMapID=nil
    lastReason="Attached: "..kind
    return true
end

-- Only requested manually; never spam the user's chat during normal play.
-- Provides a useful next diagnostic if Forever omits quest POI coordinates.
function WorldMap:DebugStatus()
    attachMap()
    if mapFrame and mapFrame:IsShown() then self:Refresh() end
    local mapID=currentMapID()
    local w,h=0,0
    if canvas then w,h=canvas:GetWidth() or 0,canvas:GetHeight() or 0 end
    local function report(message)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffe8bb59XenQuest map:|r "..message)
        elseif type(print)=="function" then
            print("XenQuest map: "..message)
        end
    end
    report("canvas="..attachedKind..", mapID="..tostring(mapID)
        ..", size="..math.floor(w).."x"..math.floor(h))
    report("active quests="..lastQuestCount..", usable pins="..lastLocationCount
        ..", show pins="..tostring(db and db.showMapPins))
    report("status="..lastReason)
end

SLASH_XENQUESTMAPDEBUG1="/xqmapdebug"
SlashCmdList.XENQUESTMAPDEBUG=function() WorldMap:DebugStatus() end

function WorldMap:Initialize(database)
    db=database
    if db.showMapPins==nil then db.showMapPins=true end
    ticker:SetScript("OnUpdate",function(_,dt)
        accumulated=accumulated+dt
        if accumulated<0.75 then return end
        accumulated=0
        if not attachMap() then return end
        if mapFrame:IsShown() then WorldMap:Refresh() end
    end)
    attachMap()
    if mapFrame and mapFrame:IsShown() then self:Refresh() end
end
