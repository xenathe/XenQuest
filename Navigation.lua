-- XenQuest experimental waypoint widget for WoW Forever.
-- Uses only Blizzard-supplied quest waypoints, never inferred coordinates.
local _,addon=...
local Navigation={}
addon.Navigation=Navigation
local frame,arrow,arrowBlend,arrowGlow,arrowBlendGlow,title,distance,db
local elapsed=0
local atan2=math.atan2 or function(y,x) return math.atan(y,x) end
local turnShimmer,lastRelativeAngle=0,nil
-- A forced selection bridges Forever's asynchronous super-tracking changes.
-- Automatic fallback is only armed when the active quest really disappears.
local forcedQuestID,selectedQuestID,lastActiveQuestID
local lastNativeQuestID=0
local navigationManuallyStopped=false
local fallbackPending,fallbackStarted,fallbackExcluded
local fallbackAttemptsAt=0
local lastValidityAt,lastValidityID,lastValidityValue=0,nil,nil
local function call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d=pcall(fn,...)
    if ok then return a,b,c,d end
end
local function chosenQuest()
    if C_SuperTrack and type(C_SuperTrack.GetSuperTrackedQuestID)=="function" then
        return call(C_SuperTrack.GetSuperTrackedQuestID)
    end
    if type(GetSuperTrackedQuestID)=="function" then return call(GetSuperTrackedQuestID) end
end
local function questTitle(questID)
    if C_QuestLog and type(C_QuestLog.GetTitleForQuestID)=="function" then
        return call(C_QuestLog.GetTitleForQuestID,questID)
    end
end
local cachedID, cachedAt, cachedMap, cachedX, cachedY
local function validPoint(mapID,x,y)
    return type(mapID)=="number" and type(x)=="number" and type(y)=="number"
        and x>=0 and x<=1 and y>=0 and y<=1
end
local function findMapPOI(questID)
    local now=(type(GetTime)=="function" and GetTime()) or 0
    if cachedID==questID and now-cachedAt<1.5 then return cachedMap,cachedX,cachedY end
    cachedID,cachedAt,cachedMap,cachedX,cachedY=questID,now,nil,nil,nil
    if not C_Map or not C_QuestLog then return end
    local current=call(C_Map.GetBestMapForUnit,"player")
    local maps,seen={},{}
    local function addMap(id)
        if type(id)=="number" and id>0 and not seen[id] then maps[#maps+1]=id;seen[id]=true end
    end
    addMap(current)
    local id=current
    for _=1,4 do
        local info=call(C_Map.GetMapInfo,id)
        if type(info)~="table" or not info.parentMapID or info.parentMapID==0 then break end
        id=info.parentMapID;addMap(id)
    end
    addMap(call(C_QuestLog.GetMapForQuestPOIs))
    addMap(call(C_QuestLog.GetQuestUiMapID,questID))
    for _,mapID in ipairs(maps) do
        local x,y=call(C_QuestLog.GetNextWaypointForMap,questID,mapID)
        if validPoint(mapID,x,y) then
            cachedMap,cachedX,cachedY=mapID,x,y
            return cachedMap,cachedX,cachedY
        end
        local pois=call(C_QuestLog.GetQuestsOnMap,mapID)
        if type(pois)=="table" then
            for _,poi in pairs(pois) do
                if type(poi)=="table" and poi.questID==questID then
                    local poiMap=poi.mapID or mapID
                    if validPoint(poiMap,poi.x,poi.y) and not poi.isQuestStart then
                        cachedMap,cachedX,cachedY=poiMap,poi.x,poi.y
                        return cachedMap,cachedX,cachedY
                    end
                end
            end
        end
    end
end
local function waypointVector(questID)
    if not C_QuestLog or not C_Map or not CreateVector2D then return nil end
    local mapID,x,y=call(C_QuestLog.GetNextWaypoint,questID)
    if not validPoint(mapID,x,y) then mapID,x,y=findMapPOI(questID) end
    if not validPoint(mapID,x,y) or not C_Map.GetWorldPosFromMapPos then return nil end
    local playerMap=call(C_Map.GetBestMapForUnit,"player")
    local playerPos=playerMap and call(C_Map.GetPlayerMapPosition,playerMap,"player")
    if not playerPos then return nil end
    local playerInstance,playerWorld=call(C_Map.GetWorldPosFromMapPos,playerMap,playerPos)
    local targetInstance,targetWorld=call(C_Map.GetWorldPosFromMapPos,mapID,CreateVector2D(x,y))
    if not playerWorld or not targetWorld or playerInstance~=targetInstance then return nil end
    local px,py=call(playerWorld.GetXY,playerWorld)
    local tx,ty=call(targetWorld.GetXY,targetWorld)
    if type(px)~="number" or type(py)~="number" or type(tx)~="number" or type(ty)~="number" then return nil end
    return tx-px,ty-py
end
-- Quest-log enumeration is deliberately independent of XenQuest's visible
-- tracker: a player may have hidden or unwatched quests that remain navigable.
local function activeQuestList()
    local total=call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    if type(total)~="number" and type(GetNumQuestLogEntries)=="function" then
        total=call(GetNumQuestLogEntries)
    end
    if type(total)~="number" or total<=0 then return nil end
    local quests={}
    for index=1,math.min(total,600) do
        local info=call(C_QuestLog and C_QuestLog.GetInfo,index)
        local id,complete,header
        if type(info)=="table" then
            id=info.questID
            complete=info.isComplete==true or info.isComplete==1
            header=info.isHeader
        elseif type(GetQuestLogTitle)=="function" then
            local _,_,_,isHeader,_,isComplete,_,questID=call(GetQuestLogTitle,index)
            id,header,complete=questID,isHeader,isComplete==true or isComplete==1
        end
        if not header and type(id)=="number" and id>0 then
            quests[#quests+1]={id=id,complete=complete}
        end
    end
    return quests
end
local function isQuestActive(questID)
    if type(questID)~="number" or questID<=0 then return false end
    local now=(type(GetTime)=="function" and GetTime()) or 0
    if lastValidityID==questID and now-lastValidityAt<0.9 then
        return lastValidityValue
    end
    local quests=activeQuestList()
    if not quests then return nil end -- Quest log may still be loading.
    local found=false
    for _,quest in ipairs(quests) do
        if quest.id==questID then found=true; break end
    end
    lastValidityID,lastValidityAt,lastValidityValue=questID,now,found
    return found
end
local function nearestQuest(excludedID)
    local quests=activeQuestList()
    if not quests then return nil end
    local bestID,bestDist,bestComplete
    for _,quest in ipairs(quests) do
        if quest.id~=excludedID then
            local dx,dy=waypointVector(quest.id)
            if type(dx)=="number" and type(dy)=="number" then
                local square=dx*dx+dy*dy
                if bestDist==nil or (bestComplete and not quest.complete)
                    or (bestComplete==quest.complete and square<bestDist) then
                    bestID,bestDist,bestComplete=quest.id,square,quest.complete
                end
            end
        end
    end
    return bestID
end
local function setNativeQuest(questID)
    local fn=(C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID)
        or (type(SetSuperTrackedQuestID)=="function" and SetSuperTrackedQuestID)
    if type(fn)~="function" then return false end
    local ok,result=pcall(fn,questID)
    return ok and result~=false
end
local function startFallback(oldID)
    if navigationManuallyStopped or fallbackPending or type(oldID)~="number" or oldID<=0 then return end
    fallbackPending=true
    fallbackStarted=(type(GetTime)=="function" and GetTime()) or 0
    fallbackAttemptsAt=fallbackStarted+0.25
    fallbackExcluded=oldID
    forcedQuestID=nil
end
function Navigation:GetSelectedQuestID()
    return selectedQuestID or 0
end
function Navigation:OnQuestSelected(questID)
    fallbackPending=false
    forcedQuestID=(type(questID)=="number" and questID>0) and questID or nil
    navigationManuallyStopped=not forcedQuestID
    selectedQuestID=forcedQuestID
    if forcedQuestID then lastActiveQuestID=forcedQuestID end
    self:Refresh()
end
function Navigation:OnQuestRemoved(questID)
    -- Invalidate any pre-removal quest-log snapshot.
    lastValidityID=nil
    local removed=tonumber(questID)
    if removed and removed>0 and
        (removed==selectedQuestID or removed==lastActiveQuestID or removed==forcedQuestID) then
        startFallback(removed)
    end
end
local function tryFallback()
    if not fallbackPending then return end
    local now=(type(GetTime)=="function" and GetTime()) or 0
    if now<fallbackAttemptsAt then return end
    fallbackAttemptsAt=now+0.4
    local replacement=nearestQuest(fallbackExcluded)
    if replacement then
        fallbackPending=false
        forcedQuestID=replacement
        selectedQuestID=replacement
        lastActiveQuestID=replacement
        navigationManuallyStopped=false
        -- Keep Blizzard's own super-tracked marker in sync when allowed.
        -- The local selection works even when the API cannot be updated.
        setNativeQuest(replacement)
    elseif now-fallbackStarted>8 then
        fallbackPending=false
        forcedQuestID=nil
        selectedQuestID=nil
        lastActiveQuestID=nil -- Stop retrying if no viable destination exists.
    end
end
local ISO_FRAMES=64
local ISO_COLUMNS=8
local ISO_STEP=(math.pi*2)/ISO_FRAMES
local ATLAS_PIXELS=2048
local ISO_CELL=1/ISO_COLUMNS
local ISO_EDGE=0.5/ATLAS_PIXELS
local lastMainFrame,lastBlendFrame
local currentBearing
local function activeArrowTexture()
    return (db and db.theme=="ice") and "Interface\\AddOns\\XenQuest\\Media\\NavigationArrowIso64Ice"
        or "Interface\\AddOns\\XenQuest\\Media\\NavigationArrowIso64"
end
local function setSpriteCell(texture,index)
    local col=index%ISO_COLUMNS
    local row=math.floor(index/ISO_COLUMNS)
    texture:SetTexCoord(
        col*ISO_CELL+ISO_EDGE,(col+1)*ISO_CELL-ISO_EDGE,
        row*ISO_CELL+ISO_EDGE,(row+1)*ISO_CELL-ISO_EDGE
    )
end
local function applyThemeAsset()
    if not arrow then return end
    local tex=activeArrowTexture()
    arrow:SetTexture(tex)
    arrowBlend:SetTexture(tex)
    arrowGlow:SetTexture(tex)
    arrowBlendGlow:SetTexture(tex)
    local isIce=(db and db.theme=="ice")
    title:SetTextColor(isIce and 0.78 or 0.96, isIce and 0.90 or 0.77, isIce and 1.0 or 0.36)
    distance:SetTextColor(isIce and 0.86 or 0.88, isIce and 0.95 or 0.90, isIce and 1.0 or 0.72)
    if isIce then
        arrowGlow:SetVertexColor(0.90,0.98,1.0,1)
        arrowBlendGlow:SetVertexColor(0.90,0.98,1.0,1)
    else
        arrowGlow:SetVertexColor(1.0,0.96,0.82,1)
        arrowBlendGlow:SetVertexColor(1.0,0.96,0.82,1)
    end
end
local function selectIsometricArrow(relativeAngle)
    if not arrow or not arrowBlend or type(relativeAngle)~="number" then return end
    local clockwise=(-relativeAngle)%(math.pi*2)
    local framePosition=clockwise/ISO_STEP
    local index=math.floor(framePosition)%ISO_FRAMES
    local nextIndex=(index+1)%ISO_FRAMES
    local fraction=framePosition-math.floor(framePosition)
    if index~=lastMainFrame then
        setSpriteCell(arrow,index)
        setSpriteCell(arrowGlow,index)
        lastMainFrame=index
    end
    if nextIndex~=lastBlendFrame then
        setSpriteCell(arrowBlend,nextIndex)
        setSpriteCell(arrowBlendGlow,nextIndex)
        lastBlendFrame=nextIndex
    end
    arrowBlend:SetAlpha(fraction)
end
local function angleDiff(a,b)
    return ((a-b+math.pi)%(math.pi*2))-math.pi
end
local function shimmerAlpha(relativeAngle)
    local t=(type(GetTime)=="function" and GetTime()) or 0
    local base=((db and db.theme=="ice") and 0.10 or 0.08)
    local pulse=(math.sin(t*7+relativeAngle*2.6)+1)*0.5
    return math.min(0.34, base + turnShimmer*0.16 + pulse*0.06)
end
local function updateArrowHeading()
    if not currentBearing or not frame or not frame:IsShown() then return end
    if type(GetPlayerFacing)~="function" then return end
    local facing=call(GetPlayerFacing)
    if type(facing)=="number" then
        local relative=currentBearing-facing
        if lastRelativeAngle then
            local diff=math.abs(angleDiff(relative,lastRelativeAngle))
            if diff>0.001 then turnShimmer=math.min(1,turnShimmer+diff*2.8) end
        end
        lastRelativeAngle=relative
        selectIsometricArrow(relative)
        local alpha=shimmerAlpha(relative)
        arrowGlow:SetAlpha(alpha)
        arrowBlendGlow:SetAlpha(alpha*arrowBlend:GetAlpha())
    end
end
function Navigation:Refresh()
    if not frame or not db then return end
    local native=chosenQuest()
    if type(native)~="number" or native<0 then native=0 end
    -- A deliberate click on ! always wins. Once Blizzard catches up, use its
    -- native target again. External changes are followed when they are valid.
    if forcedQuestID then
        if native==forcedQuestID then
            forcedQuestID=nil
        elseif native>0 and native~=lastNativeQuestID
            and native~=fallbackExcluded and isQuestActive(native)==true then
            forcedQuestID=nil
            navigationManuallyStopped=false
        end
    elseif navigationManuallyStopped and native>0 and native~=lastNativeQuestID
        and isQuestActive(native)==true then
        navigationManuallyStopped=false
    end
    lastNativeQuestID=native
    local questID=navigationManuallyStopped and 0 or (forcedQuestID or native)

    -- If the server cleared super-tracking without sending the turn-in event,
    -- detect the missing *previous* quest before offering automatic fallback.
    if not fallbackPending and questID==0 and lastActiveQuestID
        and not navigationManuallyStopped and isQuestActive(lastActiveQuestID)==false then
        startFallback(lastActiveQuestID)
    end
    if not fallbackPending and questID>0 and questID==lastActiveQuestID
        and isQuestActive(questID)==false then
        startFallback(questID)
    end
    if fallbackPending then
        tryFallback()
        questID=forcedQuestID or 0
    end
    if not questID or questID==0 then
        selectedQuestID=nil
        currentBearing=nil
        lastRelativeAngle=nil
        frame:Hide()
        return
    end
    selectedQuestID=questID
    lastActiveQuestID=questID
    frame:Show()
    local name=questTitle(questID) or ("Quest "..questID)
    title:SetText(name)
    local dx,dy=waypointVector(questID)
    if not dx then
        currentBearing=nil
        arrow:Hide();arrowBlend:Hide();arrowGlow:Hide();arrowBlendGlow:Hide()
        distance:SetText("No waypoint available")
        return
    end
    arrow:Show();arrowBlend:Show();arrowGlow:Show();arrowBlendGlow:Show()
    local yards=math.sqrt(dx*dx+dy*dy)
    distance:SetText(string.format("%.0f yd",yards))
    currentBearing=atan2(dy,dx)
    updateArrowHeading()
end
function Navigation:ApplySettings()
    if not db or not frame then return end
    local nav=db.navigation or {}
    local size=tonumber(nav.arrowSize or 88) or 88
    local titleSize=tonumber(nav.titleSize or 13) or 13
    local distanceSize=tonumber(nav.distanceSize or 11) or 11
    frame:SetSize(math.max(220,size+26), size + titleSize + distanceSize + 30)
    arrow:SetSize(size,size)
    title:ClearAllPoints()
    title:SetPoint("TOP",frame,"TOP",0,-size+7)
    title:SetWidth(math.max(195,size+70))
    distance:ClearAllPoints()
    distance:SetPoint("TOP",title,"BOTTOM",0,-3)
    distance:SetWidth(math.max(195,size+70))
    pcall(title.SetFont,title,"Fonts\\FRIZQT__.TTF",math.max(11,titleSize),"OUTLINE")
    pcall(distance.SetFont,distance,"Fonts\\FRIZQT__.TTF",math.max(10,distanceSize),"")
    applyThemeAsset()
end
function Navigation:Initialize(database)
    if frame then db=database; self:ApplySettings(); self:Refresh(); return end
    db=database
    if not db.navigation then db.navigation={x=0,y=-110,scale=1,arrowSize=88,titleSize=13,distanceSize=11} end
    local pos=db.navigation
    frame=CreateFrame("Frame","XenQuestNavigationWidget",UIParent)
    frame:SetSize(220,140)
    frame:SetPoint("TOP",UIParent,"TOP",pos.x or 0,pos.y or -110)
    frame:SetScale(pos.scale or 1)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter();local ux,uy=UIParent:GetCenter()
        local sc=self:GetEffectiveScale()/UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        db.navigation.x=(cx-ux)*sc
        db.navigation.y=(cy-uy)*sc
        self:SetPoint("CENTER",UIParent,"CENTER",db.navigation.x,db.navigation.y)
    end)
    arrow=frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(88,88)
    arrow:SetPoint("TOP",frame,"TOP",0,0)
    arrowBlend=frame:CreateTexture(nil,"ARTWORK")
    arrowBlend:SetAllPoints(arrow)
    arrowBlend:SetAlpha(0)
    arrowGlow=frame:CreateTexture(nil,"OVERLAY")
    arrowGlow:SetAllPoints(arrow)
    arrowGlow:SetBlendMode("ADD")
    arrowGlow:SetAlpha(0.12)
    arrowBlendGlow=frame:CreateTexture(nil,"OVERLAY")
    arrowBlendGlow:SetAllPoints(arrow)
    arrowBlendGlow:SetBlendMode("ADD")
    arrowBlendGlow:SetAlpha(0)
    setSpriteCell(arrow,0)
    setSpriteCell(arrowBlend,1)
    setSpriteCell(arrowGlow,0)
    setSpriteCell(arrowBlendGlow,1)
    lastMainFrame=0
    lastBlendFrame=1
    title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetWidth(195)
    title:SetJustifyH("CENTER")
    distance=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    distance:SetWidth(195)
    distance:SetJustifyH("CENTER")
    frame:SetScript("OnUpdate",function(self,dt)
        elapsed=elapsed+dt
        if elapsed>=0.15 then elapsed=0;Navigation:Refresh() end
        if turnShimmer>0 then turnShimmer=math.max(0,turnShimmer-dt*0.9) end
        updateArrowHeading()
    end)
    frame:SetScript("OnEnter",function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetText("Drag to move XenQuest navigation")
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    self:ApplySettings()
    self:Refresh()
end
