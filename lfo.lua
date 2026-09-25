-- LFO: four LFOs sending MIDI CC, for the OXI E16 (firmware >= 1.2.0)
--
-- Page 1, one LFO per row:   Shape | Rate | Depth | Center
--   turn:  shape Sin Tri SawU SawD Sqr S&H | rate 20 s .. 6.4 Hz |
--          depth -100..+100 % (negative = inverted) | center value 0-127
--   push:  on/off | restart | freeze | restart all LFOs
--   The Center ring shows the live output. Turned off, an LFO sends its center
--   value, so the Center encoder works as a plain CC knob.
--
-- Page 2, setup: encoders 1-4 = CC number for LFO 1-4, 5 = MIDI channel,
--   6 = output port (0 = all).
--
-- Settings persist in scene variables: S/R/D/C/O 1-4 (shape, rate, depth,
-- center, on), cc1-cc4, ch, out.

--@assign id=1  abbr="Shp1" name="LFO1 Shape"  l=0 h=127 manual=true g=1
--@assign id=17 abbr="Shp1" name="LFO1 On/Off" p=true g=1
--@assign id=2  abbr="Rat1" name="LFO1 Rate"   l=0 h=127 manual=true g=2
--@assign id=18 abbr="Rat1" name="LFO1 Restart" p=true g=2
--@assign id=3  abbr="Dep1" name="LFO1 Depth"  l=0 h=127 manual=true g=3
--@assign id=19 abbr="Dep1" name="LFO1 Freeze" p=true g=3
--@assign id=4  abbr="Ctr1" name="LFO1 Center" l=0 h=127 manual=true g=4
--@assign id=20 abbr="Ctr1" name="Restart all" p=true g=4
--@assign id=5  abbr="Shp2" name="LFO2 Shape"  l=0 h=127 manual=true g=5
--@assign id=21 abbr="Shp2" name="LFO2 On/Off" p=true g=5
--@assign id=6  abbr="Rat2" name="LFO2 Rate"   l=0 h=127 manual=true g=6
--@assign id=22 abbr="Rat2" name="LFO2 Restart" p=true g=6
--@assign id=7  abbr="Dep2" name="LFO2 Depth"  l=0 h=127 manual=true g=7
--@assign id=23 abbr="Dep2" name="LFO2 Freeze" p=true g=7
--@assign id=8  abbr="Ctr2" name="LFO2 Center" l=0 h=127 manual=true g=8
--@assign id=24 abbr="Ctr2" name="Restart all" p=true g=8
--@assign id=9  abbr="Shp3" name="LFO3 Shape"  l=0 h=127 manual=true g=9
--@assign id=25 abbr="Shp3" name="LFO3 On/Off" p=true g=9
--@assign id=10 abbr="Rat3" name="LFO3 Rate"   l=0 h=127 manual=true g=10
--@assign id=26 abbr="Rat3" name="LFO3 Restart" p=true g=10
--@assign id=11 abbr="Dep3" name="LFO3 Depth"  l=0 h=127 manual=true g=11
--@assign id=27 abbr="Dep3" name="LFO3 Freeze" p=true g=11
--@assign id=12 abbr="Ctr3" name="LFO3 Center" l=0 h=127 manual=true g=12
--@assign id=28 abbr="Ctr3" name="Restart all" p=true g=12
--@assign id=13 abbr="Shp4" name="LFO4 Shape"  l=0 h=127 manual=true g=13
--@assign id=29 abbr="Shp4" name="LFO4 On/Off" p=true g=13
--@assign id=14 abbr="Rat4" name="LFO4 Rate"   l=0 h=127 manual=true g=14
--@assign id=30 abbr="Rat4" name="LFO4 Restart" p=true g=14
--@assign id=15 abbr="Dep4" name="LFO4 Depth"  l=0 h=127 manual=true g=15
--@assign id=31 abbr="Dep4" name="LFO4 Freeze" p=true g=15
--@assign id=16 abbr="Ctr4" name="LFO4 Center" l=0 h=127 manual=true g=16
--@assign id=32 abbr="Ctr4" name="Restart all" p=true g=16
--@assign id=33 abbr="CC1"  name="LFO1 CC"     l=0 h=127 manual=true g=17
--@assign id=34 abbr="CC2"  name="LFO2 CC"     l=0 h=127 manual=true g=18
--@assign id=35 abbr="CC3"  name="LFO3 CC"     l=0 h=127 manual=true g=19
--@assign id=36 abbr="CC4"  name="LFO4 CC"     l=0 h=127 manual=true g=20
--@assign id=37 abbr="Chan" name="MIDI channel" l=0 h=127 manual=true g=21
--@assign id=38 abbr="Out"  name="Output port" l=0 h=127 manual=true g=22

local DT = 20.1            -- real update period: firmware fires after > 20 ms
local FULL = 16383
local C_ON, C_OFF, C_FRZ = 0, 75, 50   -- LED hue rotation (0-100)
local SH = {"Sin", "Tri", "SawU", "SawD", "Sqr", "S&H"}

-- V[id], ids 1-16: row t = LFO t, columns shape (1-6), rate (0-84),
-- depth (-100..100), center (0-127). V[16 + id] holds push flags:
-- on (col 1) and freeze (col 3).
local V = {1, 36, 50, 64, 2, 24, 50, 64, 5, 48, 30, 64, 6, 30, 40, 64,
  1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0}
local LO = {1, 0, -100, 0}
local HI = {6, 84, 100, 127}
-- Setup (page 2, ids 33-38): cc1-cc4, ch, out
local SN = {"cc1", "cc2", "cc3", "cc4", "ch", "out"}
local SV = {74, 71, 1, 10, 1, 0}
local SLO = {0, 0, 0, 0, 1, 0}
local SHI = {127, 127, 127, 127, 16, 15}

local PH = {0, 0, 0, 0}          -- phase, 0-1
local RND = {0, 0, 0, 0}         -- current sample & hold value, -1..1
local LAST = {-1, -1, -1, -1}    -- last CC value sent
local idx = {}                   -- script id -> encoder index (learned)
local spage, gpage = 1, 2

local function clamp(v, lo, hi)
  return v < lo and lo or v > hi and hi or v
end

-- Scene var name for V[i]: S1 R1 D1 C1 (turns), O1 (on flag)
local function name(i)
  local k = i > 16 and 5 or (i - 1) % 4 + 1
  return ("SRDCO"):sub(k, k) .. (i - 1) % 16 // 4 + 1
end

local function hz(r) return 0.05 * 2 ^ (r / 12) end

local function send(t, v)
  if v ~= LAST[t] then
    midi.sendCC(SV[6], SV[5] - 1, SV[t], v)
    LAST[t] = v
  end
end

-- Current output of LFO t (0-127).
local function value(t)
  local b = t * 4 - 4
  if V[b + 17] == 0 then return V[b + 4] end
  local s, p = V[b + 1], PH[t]
  local w = s == 1 and math.sin(p * 6.2831853) or s == 2 and 1 - 4 * math.abs(p - 0.5)
    or s == 3 and 2 * p - 1 or s == 4 and 1 - 2 * p or s == 5 and (p < 0.5 and 1 or -1) or RND[t]
  return clamp(math.floor(V[b + 4] + V[b + 3] * 0.635 * w + 0.5), 0, 127)
end

-- Draw LFO t: the live Center ring always, the other rings and labels when full.
local function draw(t, full, pg)
  if (pg or controller.getPage()) ~= spage then return end
  local b = t * 4 - 4
  local c = V[b + 17] == 0 and C_OFF or V[b + 19] > 0 and C_FRZ or C_ON
  local set = leds.updateByIndex
  set(idx[b + 4] or b + 4, value(t) * FULL // 127, c)
  if not full then return end
  set(idx[b + 1] or b + 1, (V[b + 1] - 1) * FULL // 5, c)
  set(idx[b + 2] or b + 2, V[b + 2] * FULL // 84, c)
  set(idx[b + 3] or b + 3, math.abs(V[b + 3]) * FULL // 100, c)
  local f, d, r = slots.update, V[b + 3], hz(V[b + 2])
  f(idx[b + 1] or b + 1, SH[V[b + 1]])
  -- whole-number formatting only: the device's printf may not support %f
  local x = math.floor((r >= 1 and r or 1 / r) * 10 + 0.5)   -- tenths of Hz or s
  f(idx[b + 2] or b + 2, r < 1 and x >= 100 and (x + 5) // 10 .. "s"
    or x // 10 .. "." .. x % 10 .. (r < 1 and "s" or ""))
  f(idx[b + 3] or b + 3, (d > 0 and "+" or "") .. d)
  f(idx[b + 4] or b + 4, "" .. V[b + 4])
end

local function drawAll(pg)
  pg = pg or controller.getPage()
  for t = 1, 4 do draw(t, true, pg) end
  if pg == gpage then
    for k = 1, 6 do
      local v, i = SV[k], idx[k + 32] or k
      leds.updateByIndex(i, (v - SLO[k]) * FULL // (SHI[k] - SLO[k]), C_ON)
      slots.update(i, k < 5 and (v < 100 and "CC" or "C") .. v or k == 5 and "Ch" .. v
        or v == 0 and "All" or "O" .. v)
    end
  end
end

function system.update()
  for t = 1, 4 do
    local b = t * 4 - 4
    if V[b + 17] > 0 then
      if V[b + 19] == 0 then
        local p = PH[t] + hz(V[b + 2]) * DT / 1000
        if p >= 1 then
          p = p % 1
          RND[t] = math.random() * 2 - 1
        end
        PH[t] = p
      end
      local v = value(t)
      if v ~= LAST[t] then
        send(t, v)
        draw(t)
      end
    end
  end
end

-- Turn ids 1-16 edit the LFOs, 33-38 the setup; pushes 17-32 are on/off,
-- restart, freeze, restart all.
function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or id < 1 or id > 38 or id > 16 and id < 33 then return end
  idx[id] = e.index
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  if id > 32 then
    gpage = e.page
    local k = id - 32
    SV[k] = clamp(SV[k] + (k < 5 and d or d > 0 and 1 or -1), SLO[k], SHI[k])
    var.set(SN[k], SV[k])
    for t = 1, 4 do LAST[t] = -1 end  -- resend everything to the new destination
    drawAll(e.page)
    return
  end
  spage = e.page
  local t, k = (id + 3) // 4, (id - 1) % 4 + 1
  if k < 3 then d = d > 0 and 1 or -1 end
  V[id] = clamp(V[id] + d, LO[k], HI[k])
  var.set(name(id), V[id])
  if V[t * 4 + 13] == 0 then send(t, V[t * 4]) end   -- off: Center is a plain knob
  draw(t, true)
end

function controller.onEncoderPress(e)
  local id = e.id - 16
  if id < 1 or id > 16 then return end
  idx[id], spage = e.index, e.page
  local t, k = (id + 3) // 4, (id - 1) % 4
  if k == 0 then
    V[e.id] = 1 - V[e.id]
    var.set(name(e.id), V[e.id])
    send(t, value(t))                 -- turning off returns to the center value
  elseif k == 1 then
    PH[t] = 0
  elseif k == 2 then
    V[e.id] = 1 - V[e.id]
  else
    for i = 1, 4 do PH[i] = 0 end
  end
  drawAll(e.page)
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

local function pull()
  local g = var.get
  for i = 1, 32 do
    if i < 17 or i % 4 == 1 then
      local n = name(i)
      var.register(n, "int", V[i])
      V[i] = clamp(g(n), i < 17 and LO[(i - 1) % 4 + 1] or 0, i < 17 and HI[(i - 1) % 4 + 1] or 1)
    end
  end
  for k = 1, 6 do
    var.register(SN[k], "int", SV[k])
    SV[k] = clamp(g(SN[k]), SLO[k], SHI[k])
  end
  for t = 1, 4 do LAST[t] = -1 end
end

function page.onVarChange()
  pull()
  drawAll()
end

function page.onInit()
  pull()
  page.setTitle("LFO x4")
  for id = 1, 38 do
    if id < 17 or id > 32 then controller.set(id, {manual = true, v = 8192}) end
  end
  system.setUpdateRate(20)
  drawAll()
end
