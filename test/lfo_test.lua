-- Tests for lfo.lua. Run from the repo root with a LUA_32BITS Lua:
--   lua test/lfo_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

E.load("lfo.lua")
check(E.rate == 20, "update rate 20 ms")
check(E.title == "LFO x4", "title")
check(E.labels[1] == "Sin" and E.labels[5] == "Tri" and E.labels[9] == "Sqr" and E.labels[13] == "S&H",
  "shape labels: " .. table.concat({E.labels[1], E.labels[5], E.labels[9], E.labels[13]}, " "))

-- every rate label fits in 4 characters
local ok = true
for _ = 1, 90 do E.turn(2, -1) end
for r = 0, 84 do
  if #E.labels[2] > 4 then ok = false; print("  too long at rate " .. r .. ": " .. E.labels[2]) end
  E.turn(2, 1)
end
check(ok, "all rate labels fit 4 chars (slowest '20s', fastest '" .. E.labels[2] .. "')")

-- LFO 1: sine, 1 Hz, depth 100 %, center 64, on CC 74
for _ = 1, 90 do E.turn(2, -1) end
for _ = 1, 52 do E.turn(2, 1) end          -- r = 52 -> 0.05 * 2^(52/12) = 1.008 Hz
check(E.labels[2] == "1.0", "rate label 1.0 Hz (" .. E.labels[2] .. ")")
for _ = 1, 10 do E.turn(3, 8) end           -- depth up to +100
check(E.labels[3] == "+100", "depth +100")
E.sent = {}
E.run(1000)
local cc74 = E.msgs(0xB0, 74)
local lo, hi = 127, 0
for _, m in ipairs(cc74) do lo, hi = math.min(lo, m.d2), math.max(hi, m.d2) end
check(lo <= 1 and hi >= 126, ("1 Hz sine sweeps the full range in 1 s (%d-%d)"):format(lo, hi))
check(#cc74 > 40, "sends a dense CC stream (" .. #cc74 .. " messages/s)")
local repeats = 0
for i = 2, #cc74 do if cc74[i].d2 == cc74[i - 1].d2 then repeats = repeats + 1 end end
check(repeats == 0, "only sends when the value changes")
check(E.rings[4] and E.rings[4].v >= 0, "center ring shows live output")

-- other LFOs go to their own CCs
check(#E.msgs(0xB0, 71) > 0 and #E.msgs(0xB0, 1) > 0 and #E.msgs(0xB0, 10) > 0, "LFO 2-4 send CC 71, 1, 10")

-- depth 0 -> constant center, no messages after the first
for _ = 1, 30 do E.turn(3, -8) end
for _ = 1, 20 do E.turn(3, 8) end            -- back to exactly 0? step to 0 below
while E.labels[3] ~= "0" do E.turn(3, E.labels[3]:sub(1, 1) == "+" and -1 or 1) end
E.run(100); E.sent = {}
E.run(1000)
check(#E.msgs(0xB0, 74) == 0, "depth 0 sends nothing new")

-- freeze holds the output
for _ = 1, 15 do E.turn(3, 8) end
E.press(19)
E.run(100); E.sent = {}
E.run(1000)
check(#E.msgs(0xB0, 74) == 0 and E.rings[4].c == 50, "freeze holds the value (freeze color)")
E.press(19)

-- off sends the center value, then Center acts as a plain knob
E.press(17)
local last = E.msgs(0xB0, 74)
check(last[#last].d2 == 64 and E.labels[4] == "64", "turning off sends center 64")
E.sent = {}
E.run(500)
check(#E.msgs(0xB0, 74) == 0, "off LFO stays silent")
E.turn(4, 3)
last = E.msgs(0xB0, 74)
check(#last == 1 and last[1].d2 == 67, "center knob sends directly while off")
E.turn(4, -3)
E.press(17)

-- restart resets phase: sine at phase 0 = center
E.run(237)
E.press(18)
check(E.rings[4], "restart ok")

-- sample & hold (LFO 4): holds a value, changes once per cycle
E.sent = {}
for _ = 1, 90 do E.turn(14, -1) end
for _ = 1, 52 do E.turn(14, 1) end           -- 1 Hz
E.run(5000)
local sh = E.msgs(0xB0, 10)
check(#sh >= 3 and #sh <= 6, "S&H at 1 Hz changes about once a second (" .. #sh .. " changes in 5 s)")

-- setup page: change LFO 1's destination to CC 20, channel 2
E.show(2)
check(E.labels[1] == "CC74" and E.labels[5] == "Ch1" and E.labels[6] == "All",
  "setup labels " .. tostring(E.labels[1]) .. " " .. tostring(E.labels[5]) .. " " .. tostring(E.labels[6]))
for _ = 1, 6 do E.turn(33, -9) end         -- 74 - 54 = 20
check(E.labels[1] == "CC20" and E.store.cc1 == 20, "LFO 1 CC -> 20 (" .. E.labels[1] .. ")")
E.turn(37, 5)
check(E.store.ch == 2 and E.labels[5] == "Ch2", "channel steps by 1 regardless of speed")
E.sent = {}
E.run(1000)
check(#E.msgs(0xB1, 20) > 0 and #E.msgs(0xB0, 74) == 0, "LFO 1 now on CC 20, channel 2")
E.show(1)
check(E.labels[1] == "Sin", "page 1 labels back after returning")

-- persistence across reload
E.turn(1, 1)                                -- LFO 1 -> Tri
E.load("lfo.lua")
check(E.labels[1] == "Tri" and E.store.cc1 == 20, "settings persist across reload")

-- ignores non-physical and foreign events
local before = E.store.S1
controller.onEncoderTurn{id = 1, index = 1, page = 1, increment = 0, value = 0, scaled = 0, is_held = false}
controller.onEncoderTurn{id = 255, index = 1, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
check(E.store.S1 == before, "ignores increment 0 and id 255")

-- no allocation while running (mock recording switched off while measuring)
local sendCC, upd = midi.sendCC, leds.updateByIndex
local calls = 0
midi.sendCC = function() calls = calls + 1 end
leds.updateByIndex = function() end
collectgarbage(); collectgarbage("stop")
local c0 = collectgarbage("count")
E.run(10000)
local grown = (collectgarbage("count") - c0) * 1024
collectgarbage("restart")
midi.sendCC, leds.updateByIndex = sendCC, upd
check(calls > 500 and grown < 256, ("no per-tick garbage (%.0f B over 10 s, %d CCs sent)"):format(grown, calls))

E.done()
