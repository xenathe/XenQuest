-- Reversible, deferred Blizzard tracker visual/input suppression and quest navigation.
-- WoW Forever's objective-tracker layout can run secureexecuterange with secret
-- aura data (including on level-up). Never call Hide/Show or install OnShow hooks
-- on Blizzard-owned tracker frames; they can taint subsequent Blizzard layouts.
local _, addon = ...
local Native = {}
addon.BlizzardUI = Native

local roots = { "ObjectiveTrackerFrame", "WatchFrame", "QuestWatchFrame" }
local savedAlpha = {}
local savedMouse = setmetatable({}, { __mode = "k" })
local mouseElapsed = 0
local enabled, stopped = false, false
local elapsed = 0

local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function invoke(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    return ok and result ~= false
end

local function forbidden(frame)
    if not frame then return true end
    if frame.IsForbidden then
        local ok, result = pcall(frame.IsForbidden, frame)
        return not ok or result
    end
    return false
end

local function canSetAlpha(frame)
    if forbidden(frame) or type(frame.SetAlpha) ~= "function" then return false end
    if InCombatLockdown and InCombatLockdown() then
        -- A protected Blizzard frame must not be changed in combat. If the
        -- client cannot report its protection state, err on the safe side.
        if call(frame.IsProtected, frame) ~= false then return false end
    end
    return true
end

-- An alpha-zero frame can still own mouse hover and click targets.  In
-- particular the Forever objective tracker may show a report/F6 tooltip even
-- though it looks hidden.  Disable input on the *children and regions* too.
-- This runs only from our existing deferred OnUpdate; never hook OnShow.
local function isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret == true
end

local function safeBool(fn, target)
    local value = call(fn, target)
    if isSecret(value) then return nil end
    if value == true then return true end
    if value == false then return false end
end

local function safeRegions(frame, getter)
    if type(getter) ~= "function" then return nil end
    local ok, regions = pcall(function() return {getter(frame)} end)
    if ok then return regions end
end

local MAX_NATIVE_REGIONS = 600
local function descendants(root)
    -- Process each native child independently. Disabling only the root does
    -- not reliably suppress interactive buttons or font strings below it.
    local nodes, seen = {root}, {[root] = true}
    local cursor = 1
    while cursor <= #nodes and cursor <= MAX_NATIVE_REGIONS do
        local frame = nodes[cursor]
        cursor = cursor + 1
        if not forbidden(frame) then
            local children = safeRegions(frame, frame.GetChildren)
            local regions = safeRegions(frame, frame.GetRegions)
            for _, group in ipairs({children or {}, regions or {}}) do
                for _, child in ipairs(group) do
                    if not isSecret(child) and child and not forbidden(child) and not seen[child] then
                        seen[child] = true
                        nodes[#nodes + 1] = child
                    end
                end
            end
        end
    end
    return nodes
end

local function suppressInput(frame)
    if forbidden(frame) then return end
    local mouseState = savedMouse[frame]
    -- Preserve the separate click/motion states. IsMouseEnabled alone loses
    -- the important case of a frame that receives only one kind of event.
    if type(frame.IsMouseClickEnabled) == "function"
            and type(frame.SetMouseClickEnabled) == "function"
            and type(frame.IsMouseMotionEnabled) == "function"
            and type(frame.SetMouseMotionEnabled) == "function" then
        local click = safeBool(frame.IsMouseClickEnabled, frame)
        local motion = safeBool(frame.IsMouseMotionEnabled, frame)
        if click == true and invoke(frame.SetMouseClickEnabled, frame, false) then
            if not mouseState then mouseState = {}; savedMouse[frame] = mouseState end
            mouseState.click = true
        end
        if motion == true and invoke(frame.SetMouseMotionEnabled, frame, false) then
            if not mouseState then mouseState = {}; savedMouse[frame] = mouseState end
            mouseState.motion = true
        end
    elseif type(frame.IsMouseEnabled) == "function"
            and type(frame.EnableMouse) == "function"
            and safeBool(frame.IsMouseEnabled, frame) == true then
        if invoke(frame.EnableMouse, frame, false) then
            if not mouseState then mouseState = {}; savedMouse[frame] = mouseState end
            mouseState.mouse = true
        end
    end
end

local function restoreInput()
    for frame, state in pairs(savedMouse) do
        if not forbidden(frame) then
            if state.click and invoke(frame.SetMouseClickEnabled, frame, true) then
                state.click = nil
            end
            if state.motion and invoke(frame.SetMouseMotionEnabled, frame, true) then
                state.motion = nil
            end
            if state.mouse and invoke(frame.EnableMouse, frame, true) then
                state.mouse = nil
            end
            if not state.click and not state.motion and not state.mouse then
                savedMouse[frame] = nil
            end
        end
    end
end

local function updateInput()
    -- Never mutate Blizzard-owned input regions while in combat. If the game
    -- recreates a quest row mid-combat, let it wait for the next safe tick.
    if InCombatLockdown and InCombatLockdown() then return end
    if enabled then
        for _, name in ipairs(roots) do
            local root = _G[name]
            if not isSecret(root) and root and not forbidden(root) then
                for _, frame in ipairs(descendants(root)) do
                    suppressInput(frame)
                end
            end
        end
    else
        restoreInput()
    end
end

function Native:SetSuppressed(wanted)
    -- Called from quest events/refreshes and potentially inside Blizzard's own
    -- UI update stack: change state only. Never mutate a Blizzard frame here.
    if stopped then return end
    enabled = not not wanted
end

function Native:UpdateVisibility(dt)
    -- Called only from XenQuest's own OnUpdate, not from an OnShow hook or an
    -- ObjectiveTracker event, to keep mutations out of Blizzard's secure range.
    if stopped then return end
    local delta = type(dt) == "number" and dt or 0
    elapsed = elapsed + delta
    mouseElapsed = mouseElapsed + delta
    if elapsed < 0.25 then return end
    elapsed = elapsed % 0.25

    -- Alpha is polled every 0.25s; input regions every 0.5s. A Blizzard
    -- quest-refresh can recreate buttons, so check for newly added children.
    if mouseElapsed >= 0.5 then
        mouseElapsed = mouseElapsed % 0.5
        updateInput()
    end

    if enabled then
        for _, name in ipairs(roots) do
            local frame = _G[name]
            if frame and not forbidden(frame) then
                if savedAlpha[frame] == nil then
                    local alpha = call(frame.GetAlpha, frame)
                    if type(alpha) == "number" then savedAlpha[frame] = alpha end
                end
                if savedAlpha[frame] ~= nil and canSetAlpha(frame)
                        and call(frame.GetAlpha, frame) ~= 0 then
                    invoke(frame.SetAlpha, frame, 0)
                end
            end
        end
    else
        for frame, alpha in pairs(savedAlpha) do
            if canSetAlpha(frame) then
                if call(frame.GetAlpha, frame) == alpha or invoke(frame.SetAlpha, frame, alpha) then
                    savedAlpha[frame] = nil
                end
            end
        end
    end
end

function Native:Shutdown()
    -- Blizzard's UI is being dismantled at logout. Do not Show/Hide or alter
    -- its frames during teardown; the next login builds fresh native frames.
    stopped = true
    enabled = false
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
