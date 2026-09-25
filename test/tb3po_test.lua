-- Tests for tb3po.lua. Run from the repo root with a LUA_32BITS Lua:
--   lua test/tb3po_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

local function ons()
  local r = {}
  for _, m in ipairs(E.sent) do
    if m.st & 0xF0 == 0x90 and m.d2 > 0 then r[#r + 1] = m end
  end
  return r
end
local function pattern()                  -- note-ons of one 16-step bar, "note@step"
  E.sent = {}
  local t0 = E.now
  E.show(1); E.press(24)                  -- play
  E.run(125.5 * 16 - 1)
  E.press(24)                             -- stop
  local t = {}
  for _, m in ipairs(ons()) do t[#t + 1] = m.d1 .. "@" .. math.floor((m.t - t0) / 125.5 + 0.5) end
  return table.concat(t, " ")
end
local function notes(p) local c = 0; for _ in p:gmatch("@") do c = c + 1 end; return c end

E.store.seed, E.store.ver = 0x3F2A, 2        -- a known seed (current layout)
E.load("tb3po.lua")
E.run(60)
check(E.title == "Gen 3F2A", "first run generates from the seed (" .. E.title .. ")")
E.run(1000)
check(E.title == "TB-3PO | 120", "title returns to transport after the message (" .. E.title .. ")")
check(table.concat(E.labels, " ", 1, 8) == "D+5 L16 A Min Oct4 T0 M25 120",
  "page 1 labels: " .. table.concat(E.labels, " ", 1, 8))

-- the stored pattern plays the same every time and survives a reload
local p1 = pattern()
check(p1 ~= "" and pattern() == p1, "pattern repeats: " .. p1)
E.load("tb3po.lua")
check(pattern() == p1, "pattern persists across reload (no regenerate)")

-- notes in A minor, velocity 100 or 127 (accent)
local ok = true
for _, m in ipairs(ons()) do
  local pc = (m.d1 - 9) % 12
  if not ("0 2 3 5 7 8 10"):find("%f[%d]" .. pc .. "%f[%D]") or (m.d2 ~= 100 and m.d2 ~= 127) then ok = false end
end
check(ok, "notes in A minor, velocity 100 or 127")

-- knobs don't rewrite the pattern; Regen applies the current density to the same seed
for _ = 1, 7 do E.turn(1, -1) end        -- density +5 -> -2
check(E.labels[1] == "D-2", "density label " .. E.labels[1])
check(pattern() == p1, "turning density leaves the pattern alone")
E.press(21)
local p2 = pattern()
check(p2 ~= p1, "Regen rebuilds with the new density")
for _ = 1, 7 do E.turn(1, 1) end
E.press(21)
check(pattern() == p1, "Regen with the original density restores the original pattern")

-- Generate draws a new seed; Undo swaps back and forth
E.press(17)
E.run(60)
check(E.title:match("^Gen %x%x%x%x$") and E.title ~= "Gen 3F2A", "Generate shows the new seed (" .. E.title .. ")")
local p3 = pattern()
check(p3 ~= p1, "Generate makes a new pattern")
E.press(22)
check(pattern() == p1, "Undo restores the previous pattern")
E.press(22)
check(pattern() == p3, "Undo again swaps back (redo)")
E.press(22)

-- Mutate changes some steps but keeps most
local function steps(p)
  local t = {}
  for n, s in p:gmatch("(%d+)@(%d+)") do t[tonumber(s)] = n end
  return t
end
local changed, total = 0, 0
for _ = 1, 10 do
  local a = steps(pattern())
  E.press(18)
  local b = steps(pattern())
  for s = 0, 15 do
    total = total + 1
    if a[s] ~= b[s] then changed = changed + 1 end
  end
  E.press(22)                             -- undo keeps each trial independent
end
local frac = changed / total
check(frac > 0.02 and frac < 0.35, ("Mutate at 25%% changes some steps (%.0f%% of steps differ)"):format(frac * 100))
check(pattern() == p1, "Undo after mutate restores the pattern")

-- density ranges (via Regen)
local function count(dens)
  E.store.dens = dens; page.onVarChange("dens")
  local n = 0
  for s = 0, 19 do
    E.store.seed = s * 3001 % 65536; page.onVarChange("seed")
    E.press(21)
    n = n + notes(pattern())
  end
  return n / 20
end
local dense, sparse, neg = count(14), count(7), count(0)
check(dense > 12 and sparse < 5 and neg > 12, ("density: +7 %.1f, 0 %.1f, -7 %.1f notes per bar"):format(dense, sparse, neg))
local pcs = {}
for _, m in ipairs((function() pattern(); return ons() end)()) do pcs[(m.d1 - 9) % 12] = true end
local n = 0
for _ in pairs(pcs) do n = n + 1 end
check(n <= 2, "density -7 keeps pitches to root/2nd (" .. n .. " pitch classes)")
E.store.dens = 12; page.onVarChange("dens")

-- slides: legato and CC 65; every note released
local legato, cc = false, 0
for s = 1, 30 do
  E.store.seed = s * 977; page.onVarChange("seed")
  E.press(21)
  pattern()
  cc = cc + #E.msgs(0xB0, 65)
  local on = {}
  for _, m in ipairs(E.sent) do
    if m.st == 0x90 and m.d2 > 0 then
      for k in pairs(on) do if k ~= m.d1 then legato = true end end
      on[m.d1] = true
    elseif m.st == 0x90 then on[m.d1] = nil end
  end
end
check(legato and cc > 0, "slides overlap notes and send CC 65 (" .. cc .. " CC65s over 30 seeds)")
local held = {}
for _, m in ipairs(E.sent) do
  if m.st == 0x90 then held[m.d1] = (held[m.d1] or 0) + (m.d2 > 0 and 1 or -1) end
end
local hang = 0
for _, c in pairs(held) do hang = hang + c end
check(hang == 0, "every note-on is released")

-- restart and stop mid-note, repeatedly: update must never raise (an error stops the E16's updates)
local okR, errR = pcall(function()
  E.press(24)
  for trial = 1, 40 do
    E.run(37 * trial % 200 + 10)
    E.press(20); E.run(15); E.press(20); E.run(5); E.press(20)
    E.run(300)
    if trial % 5 == 0 then E.press(24); E.run(trial * 7); E.press(24) end
  end
  E.press(24)
end)
check(okR and E.rate > 0, "restart/stop mid-note never breaks update " .. tostring(errR or ""))

-- only encoder 8 plays/stops; encoder 3's push does nothing
E.sent = {}
E.press(19); E.run(1000)
check(#ons() == 0, "encoder 3 push no longer starts playback")

-- an error is shown, and the script keeps running
E.press(24); E.run(500)
local real = midi.sendMidi
midi.sendMidi = function() error("boom test") end
E.run(1000)
local msg = table.concat(E.labels, "", 9, 16)
check(E.title == "ERR" and msg:find("boom test"), "error shown: header '" .. E.title .. "', labels '" .. msg .. "'")
midi.sendMidi = real
E.sent = {}
E.run(1000)
check(#ons() > 0 and E.rate > 0, "keeps playing after the error clears")
E.run(5000)
check(E.title:match("^TB%-3PO") and not table.concat(E.labels, "", 9, 16):find("boom"), "message clears, strip returns")
E.press(24)

-- live controls
E.show(1)
for _ = 1, 8 do E.turn(2, -1) end
check(E.labels[2] == "L8", "length")
E.turn(4, 1)
check(E.labels[4] == "Maj", "scale")
for _ = 1, 3 do E.turn(6, 1) end
check(E.labels[6] == "T+3", "transpose")
E.turn(7, 8)
check(E.labels[7] == "M33", "mutate amount with acceleration")
E.turn(8, 8)
check(E.labels[8] == "128" and E.rate > 0, "BPM with acceleration")

-- strip
E.press(24)
E.run(125.5 * 3)
local labs = {}
for i = 9, 16 do labs[#labs + 1] = E.labels[i] end
local play = false
for i = 9, 16 do if E.rings[i] and E.rings[i].c == 50 then play = true end end
check(#labs == 8 and play, "strip labels + playhead: " .. table.concat(labs, " "))
E.press(24)

-- settings page
E.show(2)
check(table.concat(E.labels, " ", 1, 5) == "1/16 50% CC65 Ch1 All", "settings labels: " .. table.concat(E.labels, " ", 1, 5))
E.turn(35, -1); E.turn(35, -1)
check(E.labels[3] == "Off", "slide off")
E.show(5)
check(next(E.labels) == nil and next(E.rings) == nil, "other pages left clean")

-- ignores foreign events; no garbage while playing
controller.onEncoderTurn{id = 255, index = 1, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
local sm, sc, upd, su = midi.sendMidi, midi.sendCC, leds.updateByIndex, slots.update
local nop = function() end
midi.sendMidi, midi.sendCC, leds.updateByIndex, slots.update = nop, nop, nop, nop
E.show(2); E.press(49); E.run(2000)
collectgarbage(); collectgarbage("stop")
local c0 = collectgarbage("count")
E.run(10000)
local grown = (collectgarbage("count") - c0) * 1024
collectgarbage("restart")
midi.sendMidi, midi.sendCC, leds.updateByIndex, slots.update = sm, sc, upd, su
check(grown < 256, ("no per-tick garbage (%.0f B over 10 s)"):format(grown))

E.done()
