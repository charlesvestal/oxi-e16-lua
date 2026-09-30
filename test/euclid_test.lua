-- Tests for euclid.lua. Run from the repo root with a LUA_32BITS Lua:
--   lua test/euclid_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

local function press(k) E.press(16 + k) end      -- page 1 push on encoder k
local function sturn(k, inc) E.turn(32 + k, inc) end
local function noteOns(from, to, n)
  local r = {}
  for _, m in ipairs(E.sent) do
    if m.t >= from and m.t < to and m.st & 0xF0 == 0x90 and m.d2 > 0 and (not n or m.d1 == n) then r[#r + 1] = m end
  end
  return r
end

-- reference Bjorklund via Euclid's algorithm (sequence grouping)
local function bjorklund(k, n)
  if k == 0 then local s = {} for i = 1, n do s[i] = 0 end return s end
  local a, b = {}, {}
  for i = 1, k do a[i] = {1} end
  for i = 1, n - k do b[i] = {0} end
  while #b > 1 do
    local na, nb = {}, {}
    local m = math.min(#a, #b)
    for i = 1, m do local x = {table.unpack(a[i])} for _, v in ipairs(b[i]) do x[#x + 1] = v end na[i] = x end
    for i = m + 1, #a do nb[#nb + 1] = a[i] end
    for i = m + 1, #b do nb[#nb + 1] = b[i] end
    a, b = na, nb
  end
  local s = {}
  for _, g in ipairs(a) do for _, v in ipairs(g) do s[#s + 1] = v end end
  for _, g in ipairs(b) do for _, v in ipairs(g) do s[#s + 1] = v end end
  return s
end
local function isRotation(x, y)
  if #x ~= #y then return false end
  local n = #x
  for r = 0, n - 1 do
    local ok = true
    for i = 1, n do if x[i] ~= y[(i - 1 + r) % n + 1] then ok = false break end end
    if ok then return true end
  end
  return false
end

E.load("euclid.lua")
check(E.rate == 10, "update rate 10 ms (gates)")
check(E.listening and E.res == 96, "listens to the clock at 24 ticks per quarter")
check(E.bpm == 120, "sets the internal tempo from BPM")
E.run(100)
check(E.title == "EUC \135 120", "title shows stopped + bpm ('" .. E.title .. "')")
check(E.labels[1] == "L16" and E.labels[2] == "P4" and E.labels[3] == "R0" and E.labels[4] == "C2",
  "labels for track 1")
check(E.labels[8] == "D2" and E.labels[7] == "R+4", "track 2 labels")
E.run(1000)
check(#E.sent == 0 and E.tp == nil, "no MIDI and no clock while stopped")

-- Pattern correctness for many (k, n), compared with reference Bjorklund
local allok = true
for n = 1, 32 do
  for k = 0, n do
    for _ = 1, 40 do E.turn(1, -1) end
    for _ = 2, n do E.turn(1, 1) end
    for _ = 1, 40 do E.turn(2, -1) end
    for _ = 1, k do E.turn(2, 1) end
    E.sent = {}
    local t0 = E.now
    press(3)                                    -- play: starts the internal clock
    E.run(125 * n - 1)
    press(3)                                    -- stop
    E.run(0)
    local hits = {}
    for i = 1, n do hits[i] = 0 end
    for _, m in ipairs(noteOns(t0, E.now + 1, 36)) do
      local step = math.floor((m.t - t0) / 125 + 0.5)
      if step < n then hits[step + 1] = 1 end
    end
    if not isRotation(hits, bjorklund(k, n)) then
      allok = false
      print(("  mismatch k=%d n=%d got %s"):format(k, n, table.concat(hits)))
    end
  end
end
check(allok, "E(k,n) for all 0<=k<=n<=32 match Bjorklund (up to rotation)")

-- Tempo: 16ths at 120 BPM follow the clock exactly
for _ = 1, 40 do E.turn(1, -1) end
for _ = 1, 15 do E.turn(1, 1) end               -- len 16
for _ = 1, 40 do E.turn(2, 1) end               -- pulses = 16 (every step)
E.sent = {}
local t0 = E.now
press(3)
E.run(60000 - 1)
check(E.title == "EUC \133 120", "title playing (" .. E.title .. ")")
press(3)
E.run(0)
local ons = noteOns(t0, t0 + 60000, 36)
check(#ons == 480, "480 sixteenths per minute at 120 BPM (" .. #ons .. ")")
local lo, hi = 1e9, 0
for i = 2, #ons do
  local d = ons[i].t - ons[i - 1].t
  lo, hi = math.min(lo, d), math.max(hi, d)
end
check(math.abs(lo - 125) < 0.01 and math.abs(hi - 125) < 0.01, ("steps 125 ms apart (%.2f-%.2f)"):format(lo, hi))
check(#E.msgs(0xB9, 123) >= 1, "stop sends CC 123")
check(E.tp == nil, "Play/Stop stops the internal clock it started")
local open = {}
for _, m in ipairs(E.sent) do
  if m.st & 0xF0 == 0x90 then open[m.d1] = (open[m.d1] or 0) + (m.d2 > 0 and 1 or -1) end
end
local hanging = 0
for _, c in pairs(open) do hanging = hanging + c end
check(hanging == 0, "no hanging notes after stop")
check(ons[1].st == 0x99, "sends on channel 10 (status 0x99)")

-- gate: 60 ms note-offs, timed by update
local offs = {}
for _, m in ipairs(E.sent) do if m.st == 0x99 and m.d2 == 0 and m.d1 == 36 then offs[#offs + 1] = m end end
local g = offs[1].t - ons[1].t
check(g >= 49 and g <= 61, ("gate 60 ms, within an update (%.1f)"):format(g))

-- step size follows ticks: 8T = 8 ticks = 166.7 ms at 120
E.show(2); sturn(2, -1); E.show(1)
check(E.store.div == 3, "step size 8T")
E.sent = {}; t0 = E.now
press(3); E.run(1000 - 1); press(3); E.run(0)
check(#noteOns(t0, E.now, 36) == 6, "8T: 6 steps per second at 120 (" .. #noteOns(t0, E.now, 36) .. ")")
E.show(2); sturn(2, 1); E.show(1)

-- tempo change while playing applies to the running internal clock
E.show(2)
E.press(54)                                     -- settings page play/stop
E.run(500)
sturn(1, 8); sturn(1, 8); sturn(1, 8); sturn(1, 8); sturn(1, 8)   -- 160
check(E.bpm == 160 and E.store.bpm == 160, "BPM encoder sets the internal tempo while playing")
E.sent = {}; t0 = E.now
E.run(3000)
local n160 = #noteOns(t0, E.now, 36)
check(n160 >= 31 and n160 <= 33, "plays at the new tempo (" .. n160 .. " sixteenths in 3 s at 160)")
for _ = 1, 5 do sturn(1, -8) end
E.press(54); E.run(0)
E.show(1)

-- external clock: Start restarts, the header shows its tempo, Stop stops
E.sent = {}; t0 = E.now
E.extStart(100)
E.run(2400 - 1)
check(#noteOns(t0, E.now, 36) == 16, "follows external clock (16 steps at 100 BPM in 2.4 s: " .. #noteOns(t0, E.now, 36) .. ")")
E.run(100)
check(E.title == "EUC \133 100", "header shows the external tempo (" .. E.title .. ")")
press(3)                                        -- Play/Stop: go quiet, transport keeps running
E.sent = {}; t0 = E.now
E.run(1000)
check(#noteOns(t0, E.now) == 0 and E.tp == 0, "Stop silences the tracks, external transport keeps running")
press(3)                                        -- rejoin
E.run(1000)
check(#noteOns(t0, E.now) > 0, "Play rejoins the running external transport")
E.extStop(); E.run(0)
E.sent = {}; t0 = E.now
E.run(1000)
check(#noteOns(t0, E.now) == 0 and E.title == "EUC \135 120", "external Stop stops (" .. E.title .. ")")
E.extContinue(); E.run(500)
check(#noteOns(t0, E.now) > 0, "external Continue resumes")
E.extStop(); E.extStop(); E.run(0)            -- repeated stops are harmless
local cc = #E.msgs(0xB9, 123)
check(cc >= 1, "external Stop silences")

-- mute
E.sent = {}
press(1)
check(E.labels[1] == "MUTE", "mute label")
t0 = E.now
press(3); E.run(2000); press(3); E.run(0)
check(#noteOns(t0, E.now + 1, 36) == 0, "muted track is silent")
check(#noteOns(t0, E.now + 1, 38) > 0, "other tracks still play")
press(1)

-- invert
for _ = 1, 40 do E.turn(2, -1) end; for _ = 1, 4 do E.turn(2, 1) end  -- 4 of 16
press(2)
check(E.labels[2] == "i4", "invert label")
E.sent = {}; t0 = E.now
press(3); E.run(125 * 16 - 1); press(3); E.run(0)
check(#noteOns(t0, E.now + 1, 36) == 12, "inverted E(4,16) plays 12 hits (" .. #noteOns(t0, E.now + 1, 36) .. ")")
press(2)

-- resync while playing: E(1,16) plays its hit on the next step, still on the grid
for _ = 1, 40 do E.turn(2, -1) end; E.turn(2, 1)   -- 1 of 16
E.sent = {}; t0 = E.now
press(3); E.run(125 * 5 + 10)
press(4)
local tr = E.now
E.run(125 * 3)
local after = noteOns(tr, E.now, 36)
check(#after == 1 and math.abs((after[1].t - t0) - 125 * 6) < 0.01,
  "resync: the hit plays on the next grid step (" .. (after[1] and after[1].t - t0 or -1) .. " ms)")
press(3); E.run(0)
for _ = 1, 40 do E.turn(2, 1) end

-- rotation label/clamp
for _ = 1, 40 do E.turn(3, 1) end
check(E.labels[3] == "R+15", "rotation clamps to len-1 (" .. E.labels[3] .. ")")
for _ = 1, 80 do E.turn(3, -1) end
check(E.labels[3] == "R-15", "rotation clamps to -(len-1)")
for _ = 1, 15 do E.turn(3, 1) end

-- note range and acceleration
for _ = 1, 30 do E.turn(4, 8) end
check(E.labels[4] == "G9", "note clamps to 127 = G9")
for _ = 1, 30 do E.turn(4, -8) end
check(E.labels[4] == "C-1", "note clamps to 0 = C-1")
for _ = 1, 36 do E.turn(4, 1) end

-- shrinking length clamps pulses
for _ = 1, 40 do E.turn(2, 1) end
for _ = 1, 8 do E.turn(1, -1) end
check(E.labels[2] == "P8" and E.labels[1] == "L8", "shrinking length clamps pulses")

-- bad user vars must not break anything
E.store.bpm, E.store.div, E.store.ch, E.store.gate = 0, 0, 99, -5
page.onVarChange("bpm")
local ok = pcall(function() press(3); E.run(1000); press(3); E.run(0) end)
local lastNote
for _, m in ipairs(E.sent) do if m.st & 0xF0 == 0x90 then lastNote = m end end
check(lastNote and lastNote.st == 0x9F, "channel var clamped to 16")
check(ok and E.rate == 10, "survives out-of-range scene vars")
E.store.bpm, E.store.div, E.store.ch, E.store.gate = 120, 4, 10, 60
page.onVarChange("bpm")

-- persistence
E.turn(5, -1)                                   -- track 2 len 15
E.turn(8, 2)                                    -- track 2 note 40
E.load("euclid.lua")
check(E.labels[5] == "L15" and E.labels[8] == "E2", "state restored from vars after reload")
check(E.store.trim == nil, "no trim variable")

-- device menu edits
E.store.L1, E.store.P1, E.store.N1 = 7, 3, 60
page.onVarChange("L1")
check(E.labels[1] == "L7" and E.labels[2] == "P3" and E.labels[4] == "C4", "onVarChange reloads track")
E.store.bpm = 140; page.onVarChange("bpm"); E.run(100)
check(E.title == "EUC \135 140" and E.bpm == 140, "title and internal tempo follow bpm var")

-- playhead ring moves while playing
press(3)
local seen = {}
for _ = 1, 8 do E.run(125); seen[E.rings[1].v] = true end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct >= 4, "playhead ring moves (" .. distinct .. " positions)")
press(3); E.run(0)

E.show(3)
check(next(E.labels) == nil and next(E.rings) == nil, "leaving page hands rings and labels back")
press(3); E.run(500)
check(next(E.labels) == nil and next(E.rings) == nil, "no drawing on another page")
press(3); E.run(0)

-- settings page
E.show(2)
check(E.labels[1] == "140" and E.labels[2] == "1/16" and E.labels[3] == "G60"
  and E.labels[4] == "Ch10" and E.labels[5] == "All" and E.labels[6] == "\133",
  "settings labels: " .. table.concat({tostring(E.labels[1]), tostring(E.labels[2]), tostring(E.labels[3]),
    tostring(E.labels[4]), tostring(E.labels[5]), tostring(E.labels[6])}, " "))
sturn(1, 4); E.run(100)
check(E.store.bpm == 144 and E.labels[1] == "144", "BPM encoder uses acceleration")
sturn(1, -8); sturn(1, -8); sturn(1, -8)
sturn(2, 1)
check(E.store.div == 6 and E.labels[2] == "16T", "step size 1/16 -> 16T")
sturn(2, 8)
check(E.store.div == 8 and E.labels[2] == "1/32", "step size clamps at 1/32")
sturn(2, -1); sturn(2, -1)
sturn(3, 8)
check(E.store.gate == 61, "gate moves 1 ms per detent")
for _ = 1, 3000 do sturn(3, 1) end
check(E.store.gate == 990 and E.labels[3] == "G990", "gate clamps to 990")
E.store.gate = 60; page.onVarChange("gate")
sturn(4, 1)
check(E.store.ch == 11 and E.labels[4] == "Ch11", "channel encoder")
sturn(4, -1)
sturn(5, 1)
check(E.store.out == 1 and E.labels[5] == "O1", "output encoder")
sturn(5, -1)
sturn(6, 1)
check(E.labels[6] == "\133", "turning encoder 6 does nothing")
E.press(54); E.run(100)
check(E.title == "EUC \133 120" and E.tp == 2 and E.labels[6] == "\135", "settings Play knob starts playback (" .. E.title .. ")")
E.press(54); E.run(100)
check(E.title == "EUC \135 120" and E.tp == nil, "settings push stops playback")
E.show(1)
check(E.labels[1] == "L7", "returning to page redraws")

-- non-physical value updates arrive with increment 0; id 255 = ordinary control
controller.onEncoderTurn{id = 1, index = 1, page = 1, increment = 0, value = 0, scaled = 0, is_held = false}
controller.onEncoderTurn{id = 255, index = 9, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
check(E.labels[1] == "L7", "ignores increment-0 and id-255 turn events")

-- out-of-range edits from the var menu are clamped
E.store.P1, E.store.R1, E.store.N1 = 99, -99, 300
page.onVarChange("P1")
check(E.labels[2] == "P7" and E.labels[3] == "R-6" and E.labels[4] == "G9", "var menu values clamped")
check(E.store.P1 == 7, "clamped value written back to the var")

-- no per-tick garbage while playing (the mock's own recording stubbed out)
local sendMidi, upd = midi.sendMidi, leds.updateByIndex
local calls = 0
midi.sendMidi = function() calls = calls + 1 end
leds.updateByIndex = function() end
press(3); E.run(1000)
collectgarbage(); collectgarbage("stop")
local k0 = collectgarbage("count")
E.run(10000)
local grew = (collectgarbage("count") - k0) * 1024
collectgarbage("restart")
midi.sendMidi, leds.updateByIndex = sendMidi, upd
check(calls > 50 and grew < 256, ("no per-tick garbage (%.0f B over 10 s, %d notes)"):format(grew, calls))
press(3)

-- another script's variables in the slot (32 max) are cleared, not overflowed
E.store = {}
for i = 1, 31 do E.store["old" .. i] = 1 end
local okF = pcall(E.load, "euclid.lua")
local nF = 0
for _ in pairs(E.store) do nF = nF + 1 end
check(okF and E.store.old1 == nil and E.store.ver ~= nil, "foreign variables are cleared on load (" .. nF .. " now)")

E.done()
