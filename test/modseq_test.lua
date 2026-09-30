-- Tests for modseq.lua. Run from the repo root with a LUA_32BITS Lua:
--   lua test/modseq_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

local function vals(list)
  local t = {}
  for _, m in ipairs(list) do t[#t + 1] = m.d2 end
  return t
end

E.load("modseq.lua")
check(E.listening and E.res == 96 and E.bpm == 120, "listens to the clock (24 ticks per quarter), tempo 120")
E.run(60)
check(E.title == "MOD | 120", "title stopped (" .. E.title .. ")")
check(E.labels[1] == "0" and E.labels[9] == "127" and E.labels[16] == "16", "default ramp labels")
E.run(1000)
check(#E.sent == 0, "silent while stopped")

-- play: one CC per step, stepping through the values
E.show(2)
E.sent = {}
E.press(55)
E.run(125 * 16 - 1)
check(E.title == "MOD > 120", "title playing")
local v = vals(E.msgs(0xB0, 74))
check(#v == 16, "16 steps in one bar, one CC each (" .. #v .. ")")
check(v[1] == 0 and v[9] == 127 and v[16] == 16, "values follow the steps (" .. table.concat(v, ",") .. ")")

-- step timing is even
local m = E.msgs(0xB0, 74)
local lo, hi = 1e9, 0
for i = 2, #m do
  local d = m[i].t - m[i - 1].t
  lo, hi = math.min(lo, d), math.max(hi, d)
end
check(math.abs(lo - 125) < 0.01 and math.abs(hi - 125) < 0.01, ("steps 125 ms apart (%.2f-%.2f ms)"):format(lo, hi))

-- playhead ring moves on page 1
E.show(1)
local seen = {}
for _ = 1, 6 do
  E.run(125)
  for i = 1, 16 do if E.rings[i] and E.rings[i].c == 50 then seen[i] = true end end
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
check(n >= 5, "playhead color moves across rings (" .. n .. " positions)")

-- edit a step while playing
E.turn(1, 8); E.turn(1, 2)
check(E.labels[1] == "10" and E.store.s1 == 10, "turning sets a step value (with acceleration)")

-- glide on step 1: ramps from 10 toward step 2 (16) within the step
E.press(17)
check(E.labels[1] == "~10" and E.store.glide == 1, "push toggles glide (~ label, saved)")
E.sent = {}
E.run(125 * 16)
local g = {}
for _, x in ipairs(E.msgs(0xB0, 74)) do
  if x.d2 >= 10 and x.d2 < 16 then g[#g + 1] = x.d2 end
end
check(#g >= 4, "glide sends a value per tick (" .. table.concat(g, ",") .. ")")
E.press(17)

-- length 8: only steps 1-8, steps 9-16 dark
E.show(2)
for _ = 1, 8 do E.turn(35, -1) end
check(E.labels[3] == "L8", "length 8")
E.sent = {}
E.run(125 * 16)
v = vals(E.msgs(0xB0, 74))
local max = 0
for _, x in ipairs(v) do max = math.max(max, x) end
check(max == 112, "with length 8 the peak is step 8 (112), not step 9 (" .. max .. ")")
E.show(1)
check(E.rings[12].v == 0, "steps past the length are dark")
E.show(2)
for _ = 1, 8 do E.turn(35, 1) end

-- step size and tempo change the rate
E.turn(34, -1)
check(E.labels[2] == "8T" and E.store.div == 3, "step size 1/16 -> 8T")
E.turn(34, 1)
E.turn(33, 8); E.turn(33, 2)
check(E.labels[1] == "130" and E.store.bpm == 130, "BPM with acceleration")
E.sent = {}
E.run(60000 / (130 * 4) * 16 + 1)
local c = #E.msgs(0xB0, 74)
check(c >= 15, "130 BPM plays about 16 steps per bar (" .. c .. " CCs)")
check(E.bpm == 130, "BPM sets the internal clock")

-- destination
E.turn(36, -10)
check(E.labels[4] == "CC64", "CC number")
E.sent = {}
E.run(200)
check(#E.msgs(0xB0, 64) > 0 and #E.msgs(0xB0, 74) == 0, "sends on the new CC")

-- stop
E.press(55)
E.run(60)
E.sent = {}
E.run(1000)
check(#E.sent == 0 and E.title == "MOD | 130" and E.tp == nil, "stop: silent, clock stopped, title updated")

-- external transport: follows its tempo; Continue resumes where it stopped
E.show(1)
E.sent = {}
E.extStart(90)
E.run(60000 / 90 * 4 - 1)                -- one bar of 16ths at 90
check(#E.msgs(0xB0, 64) == 16, "follows external clock: 16 steps per bar at 90 (" .. #E.msgs(0xB0, 64) .. ")")
E.run(60)
check(E.title == "MOD > 90", "header shows the external tempo (" .. E.title .. ")")
local at
for i = 1, 16 do if E.rings[i].c == 50 then at = i end end
E.extStop(); E.run(30)
check(at ~= nil and E.title == "MOD | 130", "external Stop stops")
E.extContinue(); E.run(170)
local now
for i = 1, 16 do if E.rings[i].c == 50 then now = i end end
check(now == at % 16 + 1, "Continue resumes from the step it stopped on (" .. tostring(at) .. " -> " .. tostring(now) .. ")")
E.show(2); E.press(55); E.run(0)          -- Play/Stop while external: pauses
E.sent = {}
E.run(500)
check(#E.sent == 0 and E.tp == 0, "Play/Stop pauses, external transport keeps running")
E.extStop(); E.run(0)

-- leaving for another page hands rings and labels back
E.show(5)
check(next(E.labels) == nil and next(E.rings) == nil, "page 5 is left clean")
E.show(1)
check(E.labels[1] == "10", "page 1 redrawn on return")

-- persistence
E.load("modseq.lua")
check(E.labels[1] == "10" and E.store.bpm == 130 and E.store.cc == 64, "settings persist across reload")

-- ignores foreign events
controller.onEncoderTurn{id = 255, index = 1, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
controller.onEncoderTurn{id = 1, index = 1, page = 1, increment = 0, value = 0, scaled = 0, is_held = false}
check(E.store.s1 == 10, "ignores increment 0 and id 255")

-- no per-tick garbage while playing
E.show(2)
local sendCC, upd = midi.sendCC, leds.updateByIndex
local calls = 0
midi.sendCC = function() calls = calls + 1 end
leds.updateByIndex = function() end
E.show(2); E.press(55); E.run(100)       -- (starting draws the title once)
collectgarbage(); collectgarbage("stop")
local c0 = collectgarbage("count")
E.run(10000)
local grown = (collectgarbage("count") - c0) * 1024
collectgarbage("restart")
midi.sendCC, leds.updateByIndex = sendCC, upd
check(calls > 50 and grown < 256, ("no per-tick garbage (%.0f B over 10 s, %d CCs)"):format(grown, calls))

-- another script's variables in the slot (32 max) are cleared, not overflowed
E.store = {}
for i = 1, 31 do E.store["old" .. i] = 1 end
local okF = pcall(E.load, "modseq.lua")
local nF = 0
for _ in pairs(E.store) do nF = nF + 1 end
check(okF and E.store.old1 == nil and E.store.ver ~= nil, "foreign variables are cleared on load (" .. nF .. " now)")

E.done()
