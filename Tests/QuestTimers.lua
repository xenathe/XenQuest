-- Run from the addon directory with Lua 5.1. Native timer APIs are mocked.
local harness=assert(loadfile("Tests/Completion.lua"))("harness")
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function title(h,id) return h:row(id).head.textValue end

local records={{questID=102,questTimer=299.4},{questID=101,questTimer=65}}
local calls=0
local h=harness.boot({harness.quest(101),harness.quest(102,true),harness.quest(103)},true,nil,function(env)
    env.C_QuestLog.GetQuestTimers=function() calls=calls+1;return records end
    env.SelectQuestLogEntry=function() error("Forever must not change log selection") end
    env.GetQuestLogTimeLeft=function() error("Forever must use ID-bearing timer records") end
end)
check(title(h,101):find(" (1:05)",1,true),"timer not attached by quest ID")
check(title(h,102):find(" (5:00)",1,true),"completed turn-in quest lost its active timer")
check(not title(h,103):find("(",1,true),"untimed quest received a timer")
local oldCalls=calls
h:advance(0.1)
check(calls==oldCalls,"timer API polled every frame")
records[1].questTimer=297
h:advance(0.8) -- no event: existing refresh must continue the countdown
check(title(h,102):find(" (4:57)",1,true),"countdown did not refresh without events")
table.insert(h.log,1,harness.quest(104))
h:refresh();h:settled()
check(title(h,102):find(" (4:57)",1,true),"log index changes moved a timer to another quest")
h.log[2].complete=true
h:refresh();h:settled()
check(title(h,101):find(" (1:05)",1,true),"completion sorting lost the timer")
records={{questID=101,questTimer=3661},{questID=102,questTimer=0}}
h:event("QUEST_TIMER_UPDATE");h:advance(0.36)
check(title(h,101):find(" (1:01:01)",1,true),"hour formatting failed")
check(title(h,102):find(" (0:00)",1,true),"zero remaining time was discarded")
records={}
h:advance(0.8)
check(not title(h,101):find("(",1,true) and not title(h,102):find("(",1,true),"expired timers remained visible")
records={{questID=101,questTimer=-1},{questID=102,questTimer=math.huge},
    {questID=103,questTimer=0/0},{questID=104,questTimer="60"},false}
h:refresh()
for _,id in ipairs({101,102,103,104}) do
    check(not title(h,id):find("(",1,true),"invalid timer data was displayed")
end
records={{questID=102,questTimer=60}}
for i,q in ipairs(h.log) do if q.id==102 then table.remove(h.log,i);break end end
table.insert(h.log,harness.quest(105))
h:refresh();h:settled()
check(not h:row(102) and not title(h,105):find("(",1,true),"pooled row retained an abandoned quest timer")
h.log[1].title=string.rep("Wrapped quest title ",10)
records={{questID=104,questTimer=59}}
h:refresh();h:settled()
local row=h:row(104)
check(title(h,104):find(" (0:59)",1,true) and row.titleButton:GetHeight()>17,"wrapped timer/title missing")
check(row.titleButton:GetWidth()==row.head:GetWidth(),"title/timer hit region does not match text")

local elapsed=10
local modern=harness.boot({harness.quest(201),harness.quest(202)},true,nil,function(env)
    env.C_QuestLog.GetTimeAllowed=function(id) if id==201 then return 120,elapsed end end
end)
check(title(modern,201):find(" (1:50)",1,true),"GetTimeAllowed fallback failed")
check(not title(modern,202):find("(",1,true),"GetTimeAllowed invented an untimed quest timer")
elapsed=130;modern:refresh()
check(title(modern,201):find(" (0:00)",1,true),"negative remaining duration not clamped")
modern.env.C_QuestLog.GetQuestTimers=function() return {} end
modern:refresh()
check(not title(modern,201):find("(",1,true),"empty authoritative timer list did not clear timer")
modern.env.C_QuestLog.GetQuestTimers=function() error("unsupported API") end
elapsed=11;modern:refresh()
check(title(modern,201):find(" (1:49)",1,true),"unsupported structured API did not fall back")

local selected,combat,selectionCalls=2,false,0
local legacy=harness.boot({harness.quest(301),harness.quest(302,true)},false,nil,function(env)
    env.GetQuestLogSelection=function() return selected end
    env.SelectQuestLogEntry=function(index) selected=index;selectionCalls=selectionCalls+1 end
    env.GetQuestLogTimeLeft=function() if selected==1 then return 90 end end
    env.GetQuestTimers=function() return 12345 end -- never use ambiguous positional timers
    env.InCombatLockdown=function() return combat end
end)
check(title(legacy,301):find(" (1:30)",1,true),"selected-entry legacy timer fallback failed")
check(not title(legacy,302):find("(",1,true) and selected==2,"legacy timer leaked or changed log selection")
legacy.env.GetQuestLogTimeLeft=function() error("missing timer data") end
legacy:refresh()
check(selected==2 and not title(legacy,301):find("(",1,true),"timer read error failed to restore selection")
combat=true
local before=selectionCalls
legacy:refresh()
check(selectionCalls==before,"legacy fallback changed selection in combat")
combat=false
legacy.env.GetQuestLogTimeLeft=function() if selected==1 then return 45 end end
legacy:refresh()
check(title(legacy,301):find(" (0:45)",1,true) and selected==2,"legacy timer did not recover after combat")
legacy.env.GetQuestLogSelection=nil
legacy:refresh()
check(not title(legacy,301):find("(",1,true),"legacy timer read without restorable selection")

local missing=harness.boot({harness.quest(401)},false)
check(title(missing,401)=="[10] Same quest title","absent timer APIs changed untimed titles")
print("PASS: "..checks.." quest-timer checks (Forever, ID-based and legacy APIs)")
