-- TB-3PO: generative 303-style acid sequencer, for the OXI E16 (firmware >= 1.2.0)
--
-- Port of the TB-3PO Hemisphere applet (O&C / Phazerville Hemisphere Suite) to
-- MIDI, with Generate / Mutate / Undo as in schwung-tb3po. Original: Copyright
-- (c) 2020 Logarhythm, MIT license (notice below); modified by djphazer in
-- Phazerville. This port is licensed GPL-3.0.
--
-- The knobs set the generator; the pattern only changes when you ask:
--   Generate = new seed, Regen = same seed with the current density,
--   Mutate = re-roll some steps (half get new gate/accent/slide, half a new
--   pitch), Undo = swap back to the pattern before the last change.
-- Density -7..+7: the further from 0, the more steps play; negative values
-- also narrow the pitches and repeat notes more (303-style lines). Notes gate
-- for part of a step; a slid step ties legato into the next note. Root, scale,
-- octave and transpose apply live.
--
-- Page 1, turn:  1 density | 2 length 1-32 | 3 root | 4 scale | 5 octave |
--                6 transpose | 7 mutate amount | 8 BPM
--         push:  1 generate | 2 mutate | 4 restart | 5 regen | 6 undo |
--                8 play/stop
--   Encoders 9-16 show the 8 steps around the playhead: ring = pitch, colors
--   for accent / slide / playhead; labels show the note.
-- Page 2, settings: 1 step size | 2 gate % | 3 slide (Off, Leg = legato,
--   CC65 = legato + portamento CC 65) | 4 MIDI channel | 5 output port
--
-- The pattern and settings persist in scene variables (p1-p16 hold the pattern).
-- Errors are caught and shown instead of stopping the script: the header says
-- "ERR" and the bottom 8 labels spell out the message for a few seconds.
--
-- Original TB3PO.h notice:
-- Copyright (c) 2020, Logarhythm
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


--@assign id=1  abbr="Dens" name="Density"     l=0 h=127 manual=true g=1
--@assign id=17 abbr="Dens" name="Generate"    p=true g=1
--@assign id=2  abbr="Len"  name="Length"      l=0 h=127 manual=true g=2
--@assign id=18 abbr="Len"  name="Mutate"      p=true g=2
--@assign id=3  abbr="Root" name="Root"        l=0 h=127 manual=true g=3
--@assign id=4  abbr="Scl"  name="Scale"       l=0 h=127 manual=true g=4
--@assign id=20 abbr="Scl"  name="Restart"     p=true g=4
--@assign id=5  abbr="Oct"  name="Octave"      l=0 h=127 manual=true g=5
--@assign id=21 abbr="Oct"  name="Regen"       p=true g=5
--@assign id=6  abbr="Trns" name="Transpose"   l=0 h=127 manual=true g=6
--@assign id=22 abbr="Trns" name="Undo"        p=true g=6
--@assign id=7  abbr="Mut"  name="Mutate amount" l=0 h=127 manual=true g=7
--@assign id=8  abbr="BPM"  name="Tempo"       l=0 h=127 manual=true g=8
--@assign id=24 abbr="BPM"  name="Play/Stop"   p=true g=8
--@assign id=33 abbr="Step" name="Step size"   l=0 h=127 manual=true g=17
--@assign id=34 abbr="Gate" name="Gate %"      l=0 h=127 manual=true g=18
--@assign id=35 abbr="Slid" name="Slide mode"  l=0 h=127 manual=true g=19
--@assign id=36 abbr="Chan" name="MIDI channel" l=0 h=127 manual=true g=20
--@assign id=37 abbr="Out"  name="Output port" l=0 h=127 manual=true g=21
-- pages: Acid,Set

local DT = 20.1            -- real update period: firmware fires after > rate ms
local FULL = 16383
local C_ON, C_PLAY, C_ACC, C_SLIDE = 0, 50, 85, 25   -- LED hue rotation (0-100)
local NT = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local SCL = {"023578A", "024579B", "023579A", "013578A", "024579A", "023578B", "0357A", "02479"}
local SCN = {"Min", "Maj", "Dor", "Phr", "Mix", "HMin", "PMin", "PMaj"}
local DIVS = {1, 2, 3, 4, 6, 8}
local DL = {"1/4", "1/8", "8T", "1/16", "D5", "16T", "D7", "1/32"}

-- Settings: page 1 turns (1-8), page 2 turns (9-13), and the seed (14).
local SN = {"dens", "len", "root", "scale", "oct", "tr", "mut", "bpm",
  "div", "gate", "slide", "ch", "out", "seed"}
local SV = {12, 16, 9, 1, 2, 0, 25, 120, 4, 50, 2, 1, 0, 0}
local LO = {0, 1, 0, 1, 0, -12, 5, 20, 1, 10, 0, 1, 0, 0}
local HI = {14, 32, 11, 8, 5, 12, 100, 300, 8, 100, 2, 16, 15, 65535}

-- Pattern: 9 bits per step, two steps per number (P[1] = steps 1-2 ...):
-- bits 0-3 scale degree, 4-5 octave (0 down, 1 none, 2 up), 6 gate, 7 accent, 8 slide.
local P, U = {}, {}        -- pattern and undo copy
for i = 1, 16 do P[i], U[i] = 0, 0 end

local run, step, cnt, K = false, 0, 0, 5  -- transport, step (1-32), tick in step, ticks/step
local held, left, porta = -1, 0, false    -- sounding note, ms until note-off, CC 65 on
local ticks, msgT, errT = 0, 0, 0         -- update counter; ticks left showing a message / an error
local title, shown

local function clamp(v, lo, hi)
  return v < lo and lo or v > hi and hi or v
end

local function get(s) return P[(s + 1) // 2] >> (s + 1) % 2 * 9 & 511 end

-- Deterministic LCG so a seed always gives the same pattern.
local rs = 0
local function rnd(n)
  rs = (rs * 1103515245 + 12345) & 0x7FFFFFFF
  return (rs >> 16) % n
end

-- One step's pitch (degree + octave) and flags, after TB3PO.h regenerate_pitches
-- and apply_density. what: 1 = pitch only, 2 = flags only, 3 = both.
local function roll(s, what)
  local d, size, f = SV[1], #SCL[SV[4]], get(s)
  local pcd = d < 8 and d or 8                 -- pitch-change density 0-8
  if what ~= 2 then
    local avail = pcd > 7 and size - 1 or pcd < 2 and pcd
      or clamp(3 + (pcd - 3) * math.max(size - 3, 4) // 4, 1, size - 1)
    local n = s > 1 and rnd(100) < 50 - pcd * 6 and get(s - 1) & 15 or rnd(avail + 1)
    local c = rnd(200)                         -- 40%: octave up or down
    f = f & ~63 | n | (c < 80 and (c & 1 == 1 and 2 or 0) or 1) << 4
  end
  if what ~= 1 then
    local pv = s > 1 and get(s - 1) or 0
    f = f & 63 | (rnd(100) < 10 + math.abs(d - 7) * 14 and 64 or 0)
      | (rnd(100) < (pv & 128 > 0 and 7 or 16) and 128 or 0)   -- fewer consecutive accents
      | (rnd(100) < (pv & 256 > 0 and 10 or 18) and 256 or 0)  -- fewer consecutive slides
  end
  local i, sh = (s + 1) // 2, (s + 1) % 2 * 9
  P[i] = P[i] & ~(511 << sh) | f << sh
end

local function save(undo)
  for i = 1, 16 do
    if undo then U[i] = P[i] end
    var.set("p" .. i, P[i])
  end
end

local function slid(s) return s > 0 and SV[11] > 0 and get(s) & 256 > 0 end   -- step 0 = stopped/restarted

-- MIDI note for step s.
local function pitch(s)
  local sc, f = SCL[SV[4]], get(s)
  local size = #sc
  local dg = (f & 15) + ((f >> 4 & 3) - 1) * size
  local c = sc:byte(dg % size + 1)             -- hex digit, no string allocation
  return clamp((SV[5] + 2) * 12 + SV[3] + SV[6] + dg // size * 12
    + (c > 57 and c - 55 or c - 48), 0, 127)
end

-- Note on (v > 0) or off (v = 0); n = -1 releases the sounding note.
local function note(n, v)
  if n < 0 then
    if held >= 0 then midi.sendMidi(SV[13], 0, 0x8F + SV[12], held, 0) end
    held, left = -1, 0
    n, v = 0, false
  else
    midi.sendMidi(SV[13], 0, 0x8F + SV[12], n, v)
  end
  local on = v and v > 0 and slid(step) or false
  if SV[11] == 2 and on ~= porta then          -- portamento CC 65 during slides
    midi.sendCC(SV[13], SV[12] - 1, 65, on and 127 or 0)
    porta = on
  end
end

-- Header: transport + BPM, or a short message (Gen / Mutate / Undo) for ~1 s.
local function setTitle(msg)
  if not msg and msgT > 0 then return end      -- let a message finish first
  local s = msg or (run and "TB-3PO > " or "TB-3PO | ") .. SV[8]
  if msg then msgT = 40 end
  if s ~= shown then
    page.resetTitle()                 -- title freeze workaround: set on next tick
    title, shown = s, s
  end
end

-- Pick an update rate of 20-40 ms so a step is exactly K ticks (as in Euclid).
local function timing()
  local ms = 60000 / (SV[8] * SV[9])
  local best, rate = 1e9, 20
  for k = -(-ms // 40), ms // 20 do
    local p = clamp((ms / k + 0.4) // 1, 20, 1000)
    local e = math.abs(k * (p + 0.1) - ms)
    if e < best then best, rate, K = e, p, k end
  end
  DT = rate + 0.1
  system.setUpdateRate(rate)
end

-- Pattern strip on encoders 9-16: step s, or (s = 0) the playhead's whole 8-step window.
local function strip(s, pg)
  if (pg or controller.getPage()) ~= 1 then return end
  local a = s > 0 and s or (math.max(step, 1) - 1) // 8 * 8 + 1
  for t = a, s > 0 and s or a + 7 do
    local i, n = (t - 1) % 8 + 9, pitch(t)
    local on = t <= SV[2] and (get(t) & 64 > 0 or slid(t > 1 and t - 1 or SV[2]))
    leds.updateByIndex(i, on and clamp((n - 24) * FULL // 72, 0, FULL) or 0, run and t == step and C_PLAY
      or on and get(t) & 128 > 0 and C_ACC or on and slid(t) and C_SLIDE or C_ON)
    if s == 0 and errT == 0 then slots.update(i, t > SV[2] and "" or on and NT[n % 12 + 1] or "-") end
  end
end

local function drawAll(pg)
  pg = pg or controller.getPage()
  if pg == 1 or pg == 2 then
    for i = 1, pg == 1 and 8 or 5 do
      local k = pg == 1 and i or i + 8
      local v = SV[k]
      leds.updateByIndex(i, (v - LO[k]) * FULL // (HI[k] - LO[k]), C_ON)
      slots.update(i, k == 3 and NT[v + 1] or k == 4 and SCN[v]
        or k == 9 and DL[v] or k == 11 and ({"Off", "Leg", "CC65"})[v + 1]
        or k == 13 and v == 0 and "All" or ({"D", "L", "", "", "Oct", "T", "M", "", "", "", "", "Ch", "O"})[k]
        .. ((k == 1 or k == 6) and v > (k == 1 and 7 or 0) and "+" or "")
        .. (k == 1 and v - 7 or k == 5 and v + 2 or v) .. (k == 10 and "%" or ""))
    end
    strip(0, pg)
  end
  setTitle()
end

-- Advance one step and play it (after TB3PO.h Controller()).
local function tick()
  local prev = step
  step = step % SV[2] + 1
  local from = prev > 0 and slid(prev)
  local f = get(step)
  if f & 64 > 0 or from then
    local n = pitch(step)
    if from and held >= 0 then           -- slide: legato into the new note
      if n ~= held then
        local h = held
        note(n, f & 128 > 0 and 127 or 100)
        midi.sendMidi(SV[13], 0, 0x8F + SV[12], h, 0)
      end
    else
      note(-1)
      note(n, f & 128 > 0 and 127 or 100)
    end
    held, left = n, K * DT * SV[10] / 100
  end
  if (step - 1) % 8 == 0 or prev == 0 then strip(0) else strip(prev); strip(step) end
end

local function update()
  ticks = ticks + 1
  if errT > 0 then
    errT = errT - 1
    if errT == 0 then strip(0) end
  end
  if title then page.setTitle(title); title = nil end
  if msgT > 0 then
    msgT = msgT - 1
    if msgT == 0 then setTitle() end   -- msgT is 0 here, so this shows the transport
  end
  if left > 0 then
    left = left - DT
    if left <= 0 and not slid(step) then note(-1) end
  end
  if run then
    cnt = cnt + 1
    if cnt >= K then cnt = 0; tick() end
  end
end

-- Generate the whole pattern from the seed (new = draw a new seed first).
local function generate(new)
  if new then
    SV[14] = (math.random(0, 65535) ~ ticks * 7919) & 0xFFFF
    var.set("seed", SV[14])
  end
  save(true)
  rs = SV[14] + 1
  for s = 1, 32 do roll(s, 3) end
  save()
  setTitle(("Gen %04X"):format(SV[14]))
end

-- An error in update would stop the E16's updates for good: catch it instead,
-- show "ERR" in the header and the message on the bottom 8 labels.
function system.update()
  local ok, e = pcall(update)
  if not ok then
    errT = 150
    setTitle("ERR")
    e = (tostring(e):gsub("^.-:%d+: ", ""))
    if controller.getPage() == 1 then
      for i = 0, 7 do slots.update(i + 9, e:sub(i * 4 + 1, i * 4 + 4)) end
    end
  end
end

-- Turn ids 1-8 and 33-37 change settings; pushes 17, 18, 20-22 and 24 are actions.
function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or id < 1 or id > 37 or id > 8 and id < 33 then return end
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  local k = id > 32 and id - 24 or id
  local v = SV[k]
  if k == 9 then
    local i = 1
    while DIVS[i] < v do i = i + 1 end
    v = DIVS[clamp(i + (d > 0 and 1 or -1), 1, 6)]
  else
    v = clamp(v + ((k == 7 or k == 8) and d or d > 0 and 1 or -1), LO[k], HI[k])
  end
  SV[k] = v
  var.set(SN[k], v)
  if k > 10 then note(-1) end
  timing()
  drawAll(e.page)
end

function controller.onEncoderPress(e)
  local id = e.id
  if id == 17 or id == 21 then
    generate(id == 17)
  elseif id == 18 then
    save(true)
    rs = (ticks * 7919 + SV[14]) & 0x7FFFFFFF    -- 32-bit ints: keep the product small
    for s = 1, SV[2] do
      if rnd(100) < SV[7] then roll(s, rnd(2) + 1) end
    end
    save()
    setTitle("Mutate")
  elseif id == 22 then
    for i = 1, 16 do P[i], U[i] = U[i], P[i] end
    save()
    setTitle("Undo")
  elseif id == 24 or id == 49 then
    run, cnt, step = not run, 0, 0
    note(-1)
    if run then cnt = K - 1 end       -- first update plays step 1
  elseif id == 20 then
    step, cnt = 0, K - 1
    note(-1)
  else
    return
  end
  drawAll(e.page)
end

function page.onPageChange(prev, curr)
  if prev <= 2 then
    for i = 1, 16 do
      leds.reset(i)
      slots.reset(i)
    end
  end
  drawAll(curr)                       -- getPage() may not report curr yet
end

local function pull()
  local any = false
  for k = 1, 14 do
    var.register(SN[k], "int", SV[k])
    SV[k] = clamp(var.get(SN[k]), LO[k], HI[k])
  end
  for i = 1, 16 do
    var.register("p" .. i, "int", 0)
    P[i] = var.get("p" .. i) & 0x3FFFF
    any = any or P[i] > 0
  end
  timing()
  return any
end

function page.onVarChange()
  note(-1)
  pull()
  drawAll()
end

function page.onInit()
  if not pull() then generate(SV[14] == 0) end   -- first run: make a pattern
  for id = 1, 37 do
    if id < 9 or id > 32 then controller.set(id, {manual = true, v = 8192}) end
  end
  drawAll()
end
