-- Reversible native-tracker visibility and explicit user-driven log navigation.
local _,addon=...
local Native={}
addon.BlizzardUI=Native
local roots={"ObjectiveTrackerFrame","WatchFrame","QuestWatchFrame"}
local states={}
local enabled,stopped=false,false
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c,d=pcall(fn,...)
    if ok then return a,b,c,d end
end
local function invoke(fn,...)
    if type(fn)~="function" then return false end
    local ok,result=pcall(fn,...)
    return ok and result~=false
end
local function forbidden(frame)
    if not frame then return true end
    if frame.IsForbidden then
        local ok,value=pcall(frame.IsForbidden,frame)
        return not ok or value
    end
    return false
end
local function canChange(frame)
    if forbidden(frame) then return false end
    if InCombatLockdown and InCombatLockdown() then
        return call(frame.IsProtected,frame)==false
    end
    return true
end
local function clearOwnedTooltip(root)
    if forbidden(GameTooltip) then return end
    local owner=call(GameTooltip.GetOwner,GameTooltip)
    for _=1,100 do
        if not owner then return end
        if owner==root then invoke(GameTooltip.Hide,GameTooltip);return end
        if forbidden(owner) then return end
        owner=call(owner.GetParent,owner)
    end
end
local function suppress(frame,state)
    if state.changing or not canChange(frame) then return end
    if not state.original then
        state.original={shown=call(frame.IsShown,frame),alpha=call(frame.GetAlpha,frame),mouse=call(frame.IsMouseEnabled,frame)}
        state.restoreShown=state.original.shown
    end
    state.changing=true
    -- Hiding the root also removes every descendant's hit regions. Do not
    -- unregister native events, replace scripts, reparent, or alter quest watches.
    clearOwnedTooltip(frame)
    if call(frame.IsShown,frame) then invoke(frame.Hide,frame) end
    state.changing=false
end
function Native:SetSuppressed(wanted)
    enabled=wanted and not stopped
    for _,name in ipairs(roots) do
        local frame=_G[name]
        if frame and not forbidden(frame) then
            local state=states[frame]
            if not state then state={};states[frame]=state end
            if enabled and not state.hooked and frame.HookScript and canChange(frame) then
                state.hooked=invoke(frame.HookScript,frame,"OnShow",function()
                    if enabled and not state.changing then
                        -- Remember a native request made while suppression was active.
                        if state.original then state.restoreShown=true end
                        suppress(frame,state)
                    end
                end)
            end
            if enabled then suppress(frame,state) end
        end
    end
    if enabled then return end
    for frame,state in pairs(states) do
        local original=state.original
        if original and not (InCombatLockdown and InCombatLockdown()) and canChange(frame) then
            state.changing=true
            local restored=true
            if original.alpha~=nil and call(frame.GetAlpha,frame)~=original.alpha then
                restored=invoke(frame.SetAlpha,frame,original.alpha) and restored
            end
            if original.mouse~=nil and call(frame.IsMouseEnabled,frame)~=original.mouse then
                restored=invoke(frame.EnableMouse,frame,original.mouse) and restored
            end
            if state.restoreShown~=nil and call(frame.IsShown,frame)~=state.restoreShown then
                restored=invoke(state.restoreShown and frame.Show or frame.Hide,frame) and restored
            end
            if restored then state.original=nil end
            state.changing=false
        end
    end
end
function Native:Shutdown()
    -- Logout tears down the UI; this also supplies an explicit lifecycle cleanup
    -- entry point without changing the saved preference. Hooks become inert.
    stopped=true
    self:SetSuppressed(false)
end

local function logCount()
    local count=C_QuestLog and call(C_QuestLog.GetNumQuestLogEntries)
    if type(count)~="number" or count<=0 then count=call(GetNumQuestLogEntries) end
    return type(count)=="number" and count or 0
end
function Native:ResolveQuest(q,readEntry)
    if not q then return end
    local function matches(index)
        if type(index)~="number" or index<=0 then return end
        local name,_,header,id=readEntry(index)
        if name and not header and id==q.id then return index,id end
    end
    if q.id then
        local index=C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID,q.id)
        if matches(index) then return index,q.id end
        index=call(GetQuestLogIndexByID,q.id)
        if matches(index) then return index,q.id end
        for i=1,logCount() do
            if matches(i) then return i,q.id end
        end
    else
        -- Index-only clients: accept the stored slot only when its title/level
        -- still match and are unique. Ambiguous names or changed slots fail closed.
        local found,id
        for i=1,logCount() do
            local name,level,header,currentID=readEntry(i)
            if not header and name==q.title and (tonumber(level) or 0)==q.level then
                if found then return end
                found,id=i,currentID
            end
        end
        if found==q.index then return found,id end
    end
end
function Native:QuestLink(q,readEntry)
    local index,id=self:ResolveQuest(q,readEntry)
    if not index then return end
    local function checked(link)
        if type(link)=="string" and (not id or tonumber(link:match("quest:(%d+)"))==id) then return link end
    end
    -- Legacy GetQuestLink takes an index; some clients expose an ID-based form.
    local link=checked(call(GetQuestLink,index))
    if not link and id then
        link=checked(call(GetQuestLink,id)) or checked(C_QuestLog and call(C_QuestLog.GetQuestLink,id))
    end
    return link
end
function Native:OpenQuest(q,readEntry)
    if InCombatLockdown and InCombatLockdown() then return false,"Open the quest log manually during combat." end
    -- Installed Forever compatibility code documents gamepad-binding taint/crashes
    -- when addons open its quest UI. Do not take that path in controller mode.
    if InputUtil and call(InputUtil.IsGamepadUIEnabled) then
        return false,"Open the quest log using your controller in controller mode."
    end
    local index,id=self:ResolveQuest(q,readEntry)
    if not index then return false,"This quest could not be identified in the current quest log." end
    local frame=QuestLogFrame
    if not frame and id and type(QuestMapFrame_OpenToQuestDetails)=="function" then
        if (QuestMapFrame and forbidden(QuestMapFrame)) or (WorldMapFrame and forbidden(WorldMapFrame)) then
            return false,"The native quest log is unavailable."
        end
        if invoke(QuestMapFrame_OpenToQuestDetails,id) then return true end
        return false,"The native quest log could not open this quest."
    end
    if not frame or forbidden(frame) then return false,"Quest-log navigation is unavailable on this client." end
    local function selectQuest(currentIndex,currentID)
        if type(QuestLog_SetSelection)=="function" then return invoke(QuestLog_SetSelection,currentIndex) end
        if type(SelectQuestLogEntry)=="function" then return invoke(SelectQuestLogEntry,currentIndex) end
        return currentID and C_QuestLog and invoke(C_QuestLog.SetSelectedQuest,currentID)
    end
    -- Select before opening, then resolve/select again after OnShow/layout code.
    if not selectQuest(index,id) then return false,"Quest selection is unavailable on this client." end
    if not call(frame.IsShown,frame) then
        if type(ShowUIPanel)=="function" then invoke(ShowUIPanel,frame)
        elseif type(ToggleQuestLog)=="function" then invoke(ToggleQuestLog)
        else invoke(frame.Show,frame) end
    end
    if not call(frame.IsShown,frame) then return false,"The native quest log could not be opened." end
    index,id=self:ResolveQuest(q,readEntry)
    if not index or not selectQuest(index,id) then return false,"This quest is no longer available in the quest log." end
    invoke(QuestLog_Update)
    invoke(QuestLog_UpdateQuestDetails)
    -- Scroll the legacy list without altering its quest order or watch state.
    local bar=(QuestLogListScrollFrame and QuestLogListScrollFrame.ScrollBar) or QuestLogListScrollFrameScrollBar
    if bar and not forbidden(bar) and QUESTLOG_QUEST_HEIGHT then
        local page=QUESTS_DISPLAYED or 6
        invoke(bar.SetValue,bar,math.max(0,index-math.ceil(page/2))*QUESTLOG_QUEST_HEIGHT)
    end
    return true
end
