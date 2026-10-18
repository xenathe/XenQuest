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
-- Corpse routing only overrides the display. The selected quest is not changed.
local deathSnapshot,deathWasActive=nil,false
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
-- Corpse route uses only positions reported by the client. Unlike quest
-- selection it never writes to Blizzard super-tracking or our saved settings.
local function playerIsDead()
    return call(UnitIsDeadOrGhost,"player")==true
        or call(UnitIsGhost,"player")==true or call(UnitIsDead,"player")==true
end
local function validCorpsePoint(mapID,x,y)
    return validPoint(mapID,x,y) and not (x==0 and y==0)
end
local function positionXY(pos)
    if not pos then return nil,nil end
    local x,y=call(pos.GetXY,pos)
    if type(x)=="number" and type(y)=="number" then return x,y end
    if type(pos)=="table" then return pos.x,pos.y end
end
local function mapChain(mapID)
    local ids,seen={},{}
    for _=1,6 do
        if type(mapID)~="number" or mapID<=0 or seen[mapID] then break end
        seen[mapID]=true
        ids[#ids+1]=mapID
        local info=call(C_Map and C_Map.GetMapInfo,mapID)
        mapID=type(info)=="table" and info.parentMapID or nil
    end
    return ids
end
local function snapshotDeathPosition()
    if not C_Map then return end
    local mapID=call(C_Map.GetBestMapForUnit,"player")
    local pos=mapID and call(C_Map.GetPlayerMapPosition,mapID,"player")
    local x,y=positionXY(pos)
    if validCorpsePoint(mapID,x,y) then
        deathSnapshot={mapID=mapID,x=x,y=y}
    end
end
local function corpseVector()
    if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return nil,nil end
    local playerMap=call(C_Map.GetBestMapForUnit,"player")
    if type(playerMap)~="number" then return nil,nil end
    local mapIDs=mapChain(playerMap)
    local playerInstance,playerWorld
    for _,id in ipairs(mapIDs) do
        local p=call(C_Map.GetPlayerMapPosition,id,"player")
        local x,y=positionXY(p)
        if validPoint(id,x,y) then
            local instance,world=call(C_Map.GetWorldPosFromMapPos,id,CreateVector2D(x,y))
            if type(instance)=="number" and world then
                playerInstance,playerWorld=instance,world
                break
            end
        end
    end
    if not playerWorld then return nil,nil end
    local px,py=positionXY(playerWorld)
    if type(px)~="number" or type(py)~="number" then return nil,nil end
    local getCorpse=C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
    local function vectorFor(mapID,x,y)
        if not validCorpsePoint(mapID,x,y) then return nil,nil end
        local targetInstance,targetWorld=call(C_Map.GetWorldPosFromMapPos,mapID,CreateVector2D(x,y))
        if targetWorld and playerInstance==targetInstance then
            local tx,ty=positionXY(targetWorld)
            if type(tx)=="number" and type(ty)=="number" then return tx-px,ty-py end
        end
    end
    -- Forever/Classic clients usually offer this API after releasing spirit.
    if type(getCorpse)=="function" then
        for _,id in ipairs(mapIDs) do
            local pos=call(getCorpse,id)
            local x,y=positionXY(pos)
            local dx,dy=vectorFor(id,x,y)
            if dx then return dx,dy end
        end
    end
    -- A same-session snapshot taken at PLAYER_DEAD is a cautious fallback.
    -- Never record a new location while running as a ghost at a graveyard.
    if deathSnapshot then
        return vectorFor(deathSnapshot.mapID,deathSnapshot.x,deathSnapshot.y)
    end
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
local function arrowUsesIce()
    local choice=db and db.navigation and db.navigation.arrowTheme
    if choice=="ice" then return true end
    if choice=="gold" then return false end
    return db and db.theme=="ice"
end
local function activeArrowTexture()
    return arrowUsesIce() and "Interface\\AddOns\\XenQuest\\Media\\NavigationArrowIso64Ice"
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
    local isIce=arrowUsesIce()
    local preset=(db and db.theme=="ice") and "ice" or "gold"
    local defaults={
        gold={navTitle={0.96,0.77,0.36},navDistance={0.88,0.90,0.72},navGlow={1.00,0.96,0.82}},
        ice={navTitle={0.78,0.90,1.00},navDistance={0.86,0.95,1.00},navGlow={0.90,0.98,1.00}},
    }
    local source=defaults[preset]
    local custom=(db and db.theme=="custom" and type(db.customColors)=="table") and db.customColors or nil
    local function selected(key)
        local c=custom and custom[key]
        if type(c)=="table" and type(c[1])=="number"
           and type(c[2])=="number" and type(c[3])=="number" then
            return math.max(0,math.min(1,c[1])),math.max(0,math.min(1,c[2])),math.max(0,math.min(1,c[3]))
        end
        local d=source[key]
        return d[1],d[2],d[3]
    end
    title:SetTextColor(selected("navTitle"))
    distance:SetTextColor(selected("navDistance"))
    local r,g,b=selected("navGlow")
    arrowGlow:SetVertexColor(r,g,b,1)
    arrowBlendGlow:SetVertexColor(r,g,b,1)
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
    local base=(arrowUsesIce() and 0.10 or 0.08)
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
local function refreshCorpseRoute()
    title:SetText("Your corpse")
    frame:Show()
    -- The corpse run starts after releasing spirit. Do not show an
    -- unhelpful 0-yard bearing while still lying dead on the ground.
    if call(UnitIsDead,"player")==true and call(UnitIsGhost,"player")~=true then
        currentBearing=nil
        arrow:Hide();arrowBlend:Hide();arrowGlow:Hide();arrowBlendGlow:Hide()
        distance:SetText("Release spirit to locate corpse")
        return
    end
    local dx,dy=corpseVector()
    if type(dx)~="number" or type(dy)~="number" then
        currentBearing=nil
        lastRelativeAngle=nil
        arrow:Hide();arrowBlend:Hide();arrowGlow:Hide();arrowBlendGlow:Hide()
        if call(UnitIsGhost,"player")==true then
            distance:SetText("Corpse position unavailable")
        else
            distance:SetText("Release spirit to locate corpse")
        end
        return
    end
    arrow:Show();arrowBlend:Show();arrowGlow:Show();arrowBlendGlow:Show()
    local yards=math.sqrt(dx*dx+dy*dy)
    distance:SetText(string.format("%.0f yd to corpse",yards))
    currentBearing=atan2(dy,dx)
    updateArrowHeading()
end

function Navigation:Refresh()
    if not frame or not db then return end
    if playerIsDead() then
        deathWasActive=true
        refreshCorpseRoute()
        return
    end
    if deathWasActive then
        deathWasActive=false
        deathSnapshot=nil
        -- Reset heading smoothing after returning to quest navigation.
        lastRelativeAngle=nil
    end
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
    -- Configure the working quest arrow *before* installing optional death
    -- notifications. A missing event on a modified Forever client must never
    -- prevent normal navigation from initialising.
    self:ApplySettings()
    self:Refresh()

    -- This independent, always-visible frame can wake corpse routing when the
    -- quest navigation widget itself is hidden (hidden frames do not OnUpdate).
    local deathEvents=CreateFrame("Frame")
    deathEvents:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_DEAD" then
            deathSnapshot=nil
            snapshotDeathPosition()
        elseif (event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST")
            and not playerIsDead() then
            deathSnapshot=nil
        elseif event=="PLAYER_ENTERING_WORLD" and not playerIsDead() then
            deathSnapshot=nil
        end
        Navigation:Refresh()
    end)
    -- Not all Forever builds accept every event. Register safely; never let
    -- an optional notification disable the entire navigation widget.
    for _,event in ipairs({"PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST",
        "PLAYER_ENTERING_WORLD","CORPSE_POSITION_UPDATE","ZONE_CHANGED_NEW_AREA"}) do
        pcall(deathEvents.RegisterEvent,deathEvents,event)
    end

    -- Corpse data can appear after the release event, and some clients omit
    -- CORPSE_POSITION_UPDATE. Poll ONLY during death/recovery, independently
    -- of the main navigation widget's visible state.
    local deathPollElapsed=0
    deathEvents:SetScript("OnUpdate",function(_,dt)
        deathPollElapsed=deathPollElapsed+(type(dt)=="number" and dt or 0)
        if deathPollElapsed<0.4 then return end
        deathPollElapsed=0
        if playerIsDead() or deathWasActive then
            Navigation:Refresh()
        end
    end)
end
