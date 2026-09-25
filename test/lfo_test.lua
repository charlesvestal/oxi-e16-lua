-- Tests for lfo.lua (16 LFOs on pages 1-4, settings on page 5). Run from the repo
-- root with a LUA_32BITS Lua:  lua test/lfo_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

local function turn(pg, id, inc)
  E.page = pg
  controller.onEncoderTurn{id = id, index = (id - 1) % 16 + 1, page = pg, increment = inc,
    value = 8192, scaled = 64, is_held = false}
end
local function press(pg, id)
  E.page = pg
  controller.onEncoderPress{id = id, index = (id - 1) % 16 + 1, page = pg, value = 8192, scaled = 64}
end
local function show(pg) E.show(pg); E.run(60) end
local function row(r) return table.concat(E.labels, " ", r * 4 - 3, r * 4) end
local function ccs(ch, cc)
  local r = {}
  for _, m in ipairs(E.sent) do if m.st == 0xB0 + ch - 1 and m.d1 == cc then r[#r + 1] = m.d2 end end
  return r
end
local function peaks(a)
  local n = 0
  for i = 2, #a - 1 do if a[i] >= a[i - 1] and a[i] > a[i + 1] then n = n + 1 end end
  return n
end

E.load("lfo.lua")
E.run(100)
check(E.rate == 20, "update rate 20 ms")
check(E.title == "LFO 1-4 1on", "title shows page and running count (" .. E.title .. ")")
check(E.labels[1] == "Sin" and E.labels[5] == "Tri" and E.labels[9] == "Sqr" and E.labels[13] == "S&H",
  "row shapes: " .. table.concat({E.labels[1], E.labels[5], E.labels[9], E.labels[13]}, " "))
check(row(1) == "Sin 2.5s +50 64", "row 1 labels (0.4 Hz shows its 2.5 s period): " .. row(1))

-- only LFO 1 runs by default: channel 1, CC 74
E.sent = {}
E.run(3000)
local others = 0
for _, m in ipairs(E.sent) do if not (m.st == 0xB0 and m.d1 == 74) then others = others + 1 end end
check(#ccs(1, 74) > 20 and others == 0, "only LFO 1 sends (ch1 CC74: " .. #ccs(1, 74) .. " msgs, others " .. others .. ")")

-- every free rate label fits (the mock asserts 4 characters)
for _ = 1, 90 do turn(1, 2, -1) end
check(E.labels[2] == "20s", "slowest rate 20s (" .. E.labels[2] .. ")")
for _ = 1, 90 do turn(1, 2, 1) end
check(E.labels[2] == "6.4", "fastest rate 6.4 (" .. E.labels[2] .. ")")
for _ = 1, 48 do turn(1, 2, -1) end          -- back to 36 (0.4 Hz)
check(E.labels[2] == "2.5s", "rate back to 0.4 Hz (2.5s)")

-- Dest: channel and CC per LFO
press(1, 20)
check(E.labels[1] == "Ch1" and E.labels[2] == "CC74", "Dest view: " .. row(1))
for _ = 1, 2 do turn(1, 1, 1) end
for _ = 1, 6 do turn(1, 2, -9) end           -- 74 - 54 = 20
check(E.labels[1] == "Ch3" and E.labels[2] == "CC20", "channel 3, CC 20: " .. row(1))
E.sent = {}
E.run(1500)
check(#ccs(3, 20) > 5 and #ccs(1, 74) == 0, "LFO 1 now sends ch3 CC20")
press(1, 20)
check(E.labels[1] == "Sin", "Dest off: back to shape")

-- turning LFOs on across pages; each page defaults to its own channel
press(1, 21)                                 -- row 2 on/off: LFO 2
show(2)
check(E.title == "LFO 5-8 2on" and E.labels[1] == "Sin", "page 2 (" .. E.title .. ")")
press(2, 17)                                 -- LFO 5 on
E.sent = {}
E.run(1500)
check(#ccs(1, 71) > 5 and #ccs(2, 74) > 5, "LFO 2 (ch1 CC71) and LFO 5 (ch2 CC74) run")
show(4)
check(E.title == "LFO 13-16 3on", "page 4 title (" .. E.title .. ")")

-- sync: toggling keeps about the same speed, then step to 1/4
show(1)
press(1, 18)                                 -- LFO 1: 0.4 Hz at 120 BPM = 5 beats -> 1 bar
check(E.labels[2] == "1Br", "sync picks the nearest division (" .. E.labels[2] .. ")")
turn(1, 2, 1); turn(1, 2, 1)
check(E.labels[2] == "1/4", "sync division 1/4 (" .. E.labels[2] .. ")")
for _ = 1, 2 do turn(1, 3, 25) end           -- LFO 1 depth +100
turn(1, 5, -1)                               -- LFO 2 shape Tri -> Sin
for _ = 1, 2 do turn(1, 7, 25) end           -- LFO 2 depth +100
press(1, 22)                                 -- LFO 2 sync (0.25 Hz -> 2 bars)
for _ = 1, 6 do if E.labels[6] ~= "1/4" then turn(1, 6, 1) end end
check(E.labels[6] == "1/4", "LFO 2 at 1/4 (" .. E.labels[6] .. ")")
show(5)
press(5, 49)                                 -- restart all: realign to the downbeat
E.sent = {}
E.run(4000)
local a, b = ccs(3, 20), ccs(1, 71)
check(peaks(a) >= 7 and peaks(a) <= 9, "1/4 at 120 BPM: about 8 cycles in 4 s (" .. peaks(a) .. ")")
local same = #a > 20 and #a == #b
for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then same = false end end
check(same, "two synced LFOs stay locked together")

-- BPM on the settings page drives synced rates
check(E.labels[1] == "All" and E.labels[2] == "120" and E.labels[3] == "Stop", "settings labels: " .. table.concat(E.labels, " ", 1, 3))
for _ = 1, 15 do turn(5, 34, -4) end         -- 120 -> 60
check(E.labels[2] == "60", "BPM 60 (" .. E.labels[2] .. ")")
E.sent = {}
E.run(4000)
a = ccs(3, 20)
check(peaks(a) >= 3 and peaks(a) <= 5, "1/4 at 60 BPM: about 4 cycles in 4 s (" .. peaks(a) .. ")")

-- toggling back to free keeps about the same speed (1 Hz at 60 BPM)
show(1)
press(1, 18)
check(E.labels[2] == "1.0", "back to free at the same speed (" .. E.labels[2] .. ")")

-- freeze, all off
press(1, 19)
E.run(60)
E.sent = {}
E.run(1000)
check(#ccs(3, 20) == 0 and E.rings[4].c == 50, "freeze holds LFO 1")
press(1, 19)
show(5)
press(5, 51)
E.run(100)
E.sent = {}
E.run(2000)
check(#E.sent == 0, "all off: silent")

-- persistence
E.load("lfo.lua")
E.run(100)
press(1, 20)
check(E.labels[1] == "Ch3" and E.labels[2] == "CC20", "channel/CC persist across reload: " .. row(1))
press(1, 20)
check(E.labels[2] == "1.0" and E.labels[6] == "1/4", "free and synced rates persist: " .. E.labels[2] .. " " .. E.labels[6])
local nv = 0
for _ in pairs(E.store) do nv = nv + 1 end
check(nv == 26, "uses 26 scene variables (" .. nv .. ")")

-- stale variables from an older layout are cleared rather than overflowing 32 slots
E.store = {}
for i = 1, 30 do E.store["old" .. i] = 1 end
local ok = pcall(E.load, "lfo.lua")
nv = 0
for _ in pairs(E.store) do nv = nv + 1 end
check(ok and nv == 26 and E.store.b8 ~= nil, "stale variables cleared on a layout change (" .. nv .. ")")

-- ignores non-physical and foreign events
local before = E.store.a1
turn(1, 1, 0)
controller.onEncoderTurn{id = 255, index = 1, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
check(E.store.a1 == before, "ignores increment 0 and id 255")

-- no allocation while running (mock recording off while measuring; the harness
-- itself leaves a one-off ~250 B that doesn't grow with time)
for r = 1, 4 do press(1, 13 + r * 4) end     -- all were off: LFO 1-4 on
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
check(calls > 100 and grown < 512, ("no per-tick garbage (%.0f B over 10 s, %d CCs sent)"):format(grown, calls))

E.done()
