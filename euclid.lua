-- EUCLID: 4-track Euclidean MIDI sequencer for the OXI E16 (firmware >= 1.2.0)
--
-- Page 1, one track per row:     Len   Puls   Rot   Note
--   turn:  Len 1-32 | Puls 0-Len | Rot -(Len-1)..+(Len-1) | Note 0-127
--   push:  Mute     | Invert     | Play/Stop             | Resync all tracks
--
-- Page 2, settings (encoders 1-6; push encoder 1 = Play/Stop):
--   BPM 20-300 | Step 1/4 1/8 8T 1/16 16T 1/32 | Gate 10-990 ms |
--   MIDI channel 1-16 | Output port (0 = all) | Trim (0.1% tempo, + = faster)
--
-- Everything is stored in scene variables (Scene settings > Script Variables):
--   bpm div gate ch out trim, and L/P/R/N/M/I 1-4 for the tracks.
--
-- Timing: Lua on the E16 has no MIDI clock input and no time source. The
-- firmware calls system.update() once more than `rate` ms have passed (20-1000).
-- The rate is chosen so each step is a whole number of ticks: steps are evenly
-- spaced, and the tempo is within ~1% (plus main-loop latency, which makes it
-- run slightly slow). Use "trim" to match a reference clock.
--
-- Memory: the Lua heap is ~40 KB including the VM (~12 KB). Bytecode dominates
-- script cost, so the code is table-driven (few functions) and allocates
-- nothing while playing: ~18 KB live, ~24 KB peak (32-bit heap_4 model,
-- comments stripped; the app's minifier makes it smaller).

--@assign id=1  abbr="Len1" name="T1 Length"  l=0 h=127 manual=true g=1
--@assign id=17 abbr="Len1" name="T1 Mute"    p=true g=1
--@assign id=2  abbr="Pls1" name="T1 Pulses"  l=0 h=127 manual=true g=2
--@assign id=18 abbr="Pls1" name="T1 Invert"  p=true g=2
--@assign id=3  abbr="Rot1" name="T1 Rotate"  l=0 h=127 manual=true g=3
--@assign id=19 abbr="Rot1" name="Play/Stop"  p=true g=3
--@assign id=4  abbr="Not1" name="T1 Note"    l=0 h=127 manual=true g=4
--@assign id=20 abbr="Not1" name="Resync"     p=true g=4
--@assign id=5  abbr="Len2" name="T2 Length"  l=0 h=127 manual=true g=5
--@assign id=21 abbr="Len2" name="T2 Mute"    p=true g=5
--@assign id=6  abbr="Pls2" name="T2 Pulses"  l=0 h=127 manual=true g=6
--@assign id=22 abbr="Pls2" name="T2 Invert"  p=true g=6
--@assign id=7  abbr="Rot2" name="T2 Rotate"  l=0 h=127 manual=true g=7
--@assign id=23 abbr="Rot2" name="Play/Stop"  p=true g=7
--@assign id=8  abbr="Not2" name="T2 Note"    l=0 h=127 manual=true g=8
--@assign id=24 abbr="Not2" name="Resync"     p=true g=8
--@assign id=9  abbr="Len3" name="T3 Length"  l=0 h=127 manual=true g=9
--@assign id=25 abbr="Len3" name="T3 Mute"    p=true g=9
--@assign id=10 abbr="Pls3" name="T3 Pulses"  l=0 h=127 manual=true g=10
--@assign id=26 abbr="Pls3" name="T3 Invert"  p=true g=10
--@assign id=11 abbr="Rot3" name="T3 Rotate"  l=0 h=127 manual=true g=11
--@assign id=27 abbr="Rot3" name="Play/Stop"  p=true g=11
--@assign id=12 abbr="Not3" name="T3 Note"    l=0 h=127 manual=true g=12
--@assign id=28 abbr="Not3" name="Resync"     p=true g=12
--@assign id=13 abbr="Len4" name="T4 Length"  l=0 h=127 manual=true g=13
--@assign id=29 abbr="Len4" name="T4 Mute"    p=true g=13
--@assign id=14 abbr="Pls4" name="T4 Pulses"  l=0 h=127 manual=true g=14
--@assign id=30 abbr="Pls4" name="T4 Invert"  p=true g=14
--@assign id=15 abbr="Rot4" name="T4 Rotate"  l=0 h=127 manual=true g=15
--@assign id=31 abbr="Rot4" name="Play/Stop"  p=true g=15
--@assign id=16 abbr="Not4" name="T4 Note"    l=0 h=127 manual=true g=16
--@assign id=32 abbr="Not4" name="Resync"     p=true g=16
--@assign id=33 abbr="BPM"  name="Tempo"      l=0 h=127 manual=true g=17
--@assign id=49 abbr="BPM"  name="Play/Stop (settings)" p=true g=17
--@assign id=34 abbr="Step" name="Step size"  l=0 h=127 manual=true g=18
--@assign id=35 abbr="Gate" name="Gate ms"    l=0 h=127 manual=true g=19
--@assign id=36 abbr="Chan" name="MIDI channel" l=0 h=127 manual=true g=20
--@assign id=37 abbr="Out"  name="Output port" l=0 h=127 manual=true g=21
--@assign id=38 abbr="Trim" name="Tempo trim" l=0 h=127 manual=true g=22

local DT = 20.1            -- real update period: firmware fires after > rate ms
local FULL = 16383         -- full LED ring
local C_ON, C_HIT, C_MUTE = 0, 50, 75 -- LED color: index into the app's 100-color palette

-- V[id]: ids 1-16 are the encoder values, row t = track t, columns are
-- len, pulses, rotation, note. V[16 + id] holds push flags: mute (col 1), invert (col 2).
local V = {16, 4, 0, 36, 16, 2, 4, 38, 16, 8, 0, 42, 16, 3, 2, 46}
local POS = {0, 0, 0, 0}   -- next step per track (0-based)
local LEFT = {0, 0, 0, 0}  -- ms until note-off (0 = silent)
local idx = {}             -- script id -> encoder index (learned from events)
local spage, gpage = 1, 2  -- pattern page and settings page (learned)
local run, cnt = false, 0  -- transport; ticks since the last step
local K = 5                -- update ticks per step
local bpm, gate, st, out   -- cached settings (st = note-on status)

-- Settings (page 2 encoders 1-6, ids 33-38): var name, default, range
local SET = {"bpm", "div", "gate", "ch", "out", "trim"}
local DEF = {120, 4, 60, 10, 0, 0}
local LO = {20, 1, 10, 1, 0, -99}
local HI = {300, 8, 990, 16, 15, 99}
local SV = {}              -- current (clamped) settings values
local DIVS = {1, 2, 3, 4, 6, 8}
local DL = {"1/4", "1/8", "8T", "1/16", "D5", "16T", "D7", "1/32"}
local title, shown         -- pending / displayed header text
local memT = 0             -- update ticks left showing the heap in the header

local function clamp(v, lo, hi)
  return v < lo and lo or v > hi and hi or v
end

-- Scene var name for V[i]: L1 P1 R1 N1 (turns), M1 I1 (pushes)
local function name(i)
  local k = i > 16 and (i - 17) % 4 + 5 or (i - 1) % 4 + 1
  return ("LPRNMI"):sub(k, k) .. (i - 1) % 16 // 4 + 1
end

-- Clamp track t into range and store it.
local function fix(t)
  local b = t * 4 - 4
  local n = clamp(V[b + 1], 1, 32)
  V[b + 1], V[b + 2] = n, clamp(V[b + 2], 0, n)
  V[b + 3], V[b + 4] = clamp(V[b + 3], 1 - n, n - 1), clamp(V[b + 4], 0, 127)
  POS[t] = POS[t] % n
  for j = 1, 6 do
    local i = j < 5 and b + j or b + j + 12
    var.set(name(i), V[i])
  end
end

-- Load every setting from the scene vars (registering them on first run).
local function pull()
  local g = var.get
  for i = 1, 32 do
    if i < 17 or (i - 17) % 4 < 2 then
      local n = name(i)
      var.register(n, "int", V[i] or 0)
      V[i] = g(n)
    end
  end
  for t = 1, 4 do fix(t) end
  for k = 1, 6 do SV[k] = clamp(g(SET[k]), LO[k], HI[k]) end
  bpm = SV[1]
  local ms = 60000 / (bpm * SV[2]) / (1 + SV[6] / 1000)
  -- A step is exactly K update ticks, so steps are evenly spaced. Pick the
  -- 20-40 ms rate (fine enough for gates) whose K ticks best match the step;
  -- the tempo error is at most ~1%, and "trim" nudges it.
  local best, rate = 1e9, 20
  for k = -(-ms // 40), ms // 20 do
    local p = clamp((ms / k + 0.4) // 1, 20, 1000)
    local e = math.abs(k * (p + 0.1) - ms)
    if e < best then best, rate, K = e, p, k end
  end
  DT = rate + 0.1
  system.setUpdateRate(rate)
  gate, st, out = SV[3], 0x8F + SV[4], SV[5]
end

local function off(t)
  if LEFT[t] > 0 then
    midi.sendMidi(out, 0, st, V[t * 4], 0)
    LEFT[t] = 0
  end
end

-- Draw track t: playhead + note flash always, values and labels when full.
-- Rings use physical-index overrides: on device, the normal encoder view shows
-- a manual control's stored value instead of leds.update(id) state, while
-- index overrides take priority. Both rings and labels are per physical slot,
-- so they are only drawn while the script's page is shown.
local function draw(t, full, pg)
  if (pg or controller.getPage()) ~= spage then return end
  local b = t * 4 - 4
  local n, m = V[b + 1], V[b + 17] > 0
  for k = 1, 4 do
    if full or k ~= 2 and k ~= 3 then
      local v, id = V[b + k], b + k
      local f = k == 1 and POS[t] / n or k == 2 and v / n or k == 3 and v % n / n or v / 127
      leds.updateByIndex(idx[id] or id, FULL * f // 1, k == 4 and LEFT[t] > 0 and C_HIT or m and C_MUTE or C_ON)
      if full then
        local s
        if k == 1 then s = m and "MUTE" or "L" .. n
        elseif k == 2 then s = (V[b + 18] > 0 and "i" or "P") .. v
        elseif k == 3 then s = (v > 0 and "R+" or "R") .. v
        else s = ("C C#D D#E F F#G G#A A#B "):sub(v % 12 * 2 + 1, v % 12 * 2 + 2):gsub(" ", "") .. v // 12 - 1
        end
        slots.update(idx[id] or id, s)
      end
    end
  end
end

local function drawAll(pg)
  pg = pg or controller.getPage()
  for t = 1, 4 do draw(t, true, pg) end
  if pg == gpage then
    for k = 1, 6 do
      local v, i = SV[k], idx[k + 32] or k
      leds.updateByIndex(i, (v - LO[k]) * FULL // (HI[k] - LO[k]), C_ON)
      slots.update(i, k == 1 and "" .. v or k == 2 and DL[v] or k == 3 and "G" .. v
        or k == 4 and "Ch" .. v or k == 5 and (v == 0 and "All" or "O" .. v)
        or (v > 0 and "T+" or "T") .. v)
    end
  end
  -- Title freeze workaround: reset now, set the new text on the next update.
  local s = (run and "EUC > " or "EUC | ") .. bpm
  if s ~= shown then
    page.resetTitle()
    title, shown = s, s
  end
end

-- Play one step on every track. Pulse test is the Bresenham form of Bjorklund.
local function tick()
  for t = 1, 4 do
    local b = t * 4 - 4
    local n, p = V[b + 1], V[b + 2]
    local on = ((POS[t] - V[b + 3]) % n * p) % n < p
    if on ~= (V[b + 18] > 0) and V[b + 17] == 0 then
      off(t)
      midi.sendMidi(out, 0, st, V[b + 4], 100)
      LEFT[t] = gate
    end
    POS[t] = (POS[t] + 1) % n
    draw(t)
  end
end

function system.update()
  if title then page.setTitle(title); title = nil end
  if memT > 0 then
    memT = memT - 1
    if memT == 0 then page.resetTitle(); title = shown end
  end
  for t = 1, 4 do
    local l = LEFT[t]
    if l > 0 then
      if l <= DT then off(t); draw(t) else LEFT[t] = l - DT end
    end
  end
  if run then
    cnt = cnt + 1
    if cnt >= K then cnt = 0; tick() end
  end
end

-- Turn ids 1-16 edit V, 33-38 the settings; push ids 17-32 are mute, invert,
-- play/stop, resync, and 49 is play/stop on the settings page.
function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or id < 1 or id > 38 or id > 16 and id < 33 then return end
  idx[id] = e.index
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  if id > 32 then
    gpage = e.page
    local k = id - 32
    local v = SV[k]
    if k == 2 then
      local i = 1
      while DIVS[i] < v do i = i + 1 end
      v = DIVS[clamp(i + (d > 0 and 1 or -1), 1, 6)]
    else
      v = clamp(v + (k == 1 and d or d > 0 and 1 or -1), LO[k], HI[k])
    end
    var.set(SET[k], v)
    for t = 1, 4 do off(t) end
    pull()
    drawAll()
    return
  end
  spage = e.page
  local t = (id + 3) // 4
  if id % 4 > 0 then d = d > 0 and 1 or -1 else off(t) end
  V[id] = V[id] + d
  fix(t)
  draw(t, true)
end

function controller.onEncoderPress(e)
  local id = e.id == 49 and 3 or e.id - 16
  if id < 1 or id > 16 then return end
  if e.id < 33 then idx[id], spage = e.index, e.page end
  local t, k = (id + 3) // 4, (id - 1) % 4
  if k < 2 then
    V[e.id] = 1 - V[e.id]
    off(t)
    fix(t)
  else
    for i = 1, 4 do off(i); POS[i] = 0 end
    cnt = 0
    if k == 2 then run = not run end
    if run then tick() else midi.sendCC(out, st - 0x90, 123, 0) end
  end
  drawAll()
end

function page.onPageChange(prev, curr)
  if prev == spage or prev == gpage then
    for i = 1, 16 do
      leds.reset(i)
      slots.reset(i)
    end
  end
  drawAll(curr)                       -- getPage() may not report curr yet
end

function page.onVarChange()
  for t = 1, 4 do off(t) end
  pull()
  drawAll()
end

function page.onInit()
  for k = 1, 6 do var.register(SET[k], "int", DEF[k]) end
  pull()
  -- manual: the script owns the values (the scene file may not carry the flag)
  for id = 1, 38 do
    if id < 17 or id > 32 then controller.set(id, {manual = true, v = 8192}) end
  end
  drawAll()
  -- Show Lua's own heap count (excludes allocator overhead) for ~2 s.
  collectgarbage()
  local kb = math.floor(collectgarbage("count"))
  print("euclid: Lua heap " .. kb .. " KB")
  title, memT = "EUC heap " .. kb .. "KB", 75
end
