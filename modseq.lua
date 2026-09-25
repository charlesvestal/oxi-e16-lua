-- MODSEQ: 16-step CC modulation sequencer, for the OXI E16 (firmware >= 1.2.0)
--
-- Page 1: one step per encoder.
--   turn: step value 0-127 | push: glide on/off (ramp to the next step's value)
--   Rings show the values; the playhead lights up, glide steps have their own
--   color, and steps past the length go dark. Labels show values ("~64" = glide).
-- Page 2, settings (push encoder 1 = play/stop):
--   BPM 20-300 | step 1/4 1/8 8T 1/16 16T 1/32 | length 1-16 | CC number |
--   MIDI channel | output port (0 = all) | trim (0.1% tempo, + = faster)
--
-- Timing: no clock input exists for Lua; like Euclid, each step is a whole
-- number of update ticks (20-40 ms), so steps are even and the tempo is
-- within ~1%. Glides move in tick-sized increments.
--
-- Settings persist in scene variables: s1-s16 (values), glide (bit mask),
-- bpm div len cc ch out trim.

--@assign id=1  abbr="S1"  name="Step 1"  l=0 h=127 manual=true g=1
--@assign id=17 abbr="S1"  name="Glide 1" p=true g=1
--@assign id=2  abbr="S2"  name="Step 2"  l=0 h=127 manual=true g=2
--@assign id=18 abbr="S2"  name="Glide 2" p=true g=2
--@assign id=3  abbr="S3"  name="Step 3"  l=0 h=127 manual=true g=3
--@assign id=19 abbr="S3"  name="Glide 3" p=true g=3
--@assign id=4  abbr="S4"  name="Step 4"  l=0 h=127 manual=true g=4
--@assign id=20 abbr="S4"  name="Glide 4" p=true g=4
--@assign id=5  abbr="S5"  name="Step 5"  l=0 h=127 manual=true g=5
--@assign id=21 abbr="S5"  name="Glide 5" p=true g=5
--@assign id=6  abbr="S6"  name="Step 6"  l=0 h=127 manual=true g=6
--@assign id=22 abbr="S6"  name="Glide 6" p=true g=6
--@assign id=7  abbr="S7"  name="Step 7"  l=0 h=127 manual=true g=7
--@assign id=23 abbr="S7"  name="Glide 7" p=true g=7
--@assign id=8  abbr="S8"  name="Step 8"  l=0 h=127 manual=true g=8
--@assign id=24 abbr="S8"  name="Glide 8" p=true g=8
--@assign id=9  abbr="S9"  name="Step 9"  l=0 h=127 manual=true g=9
--@assign id=25 abbr="S9"  name="Glide 9" p=true g=9
--@assign id=10 abbr="S10" name="Step 10" l=0 h=127 manual=true g=10
--@assign id=26 abbr="S10" name="Glide 10" p=true g=10
--@assign id=11 abbr="S11" name="Step 11" l=0 h=127 manual=true g=11
--@assign id=27 abbr="S11" name="Glide 11" p=true g=11
--@assign id=12 abbr="S12" name="Step 12" l=0 h=127 manual=true g=12
--@assign id=28 abbr="S12" name="Glide 12" p=true g=12
--@assign id=13 abbr="S13" name="Step 13" l=0 h=127 manual=true g=13
--@assign id=29 abbr="S13" name="Glide 13" p=true g=13
--@assign id=14 abbr="S14" name="Step 14" l=0 h=127 manual=true g=14
--@assign id=30 abbr="S14" name="Glide 14" p=true g=14
--@assign id=15 abbr="S15" name="Step 15" l=0 h=127 manual=true g=15
--@assign id=31 abbr="S15" name="Glide 15" p=true g=15
--@assign id=16 abbr="S16" name="Step 16" l=0 h=127 manual=true g=16
--@assign id=32 abbr="S16" name="Glide 16" p=true g=16
--@assign id=33 abbr="BPM"  name="Tempo"        l=0 h=127 manual=true g=17
--@assign id=49 abbr="BPM"  name="Play/Stop"    p=true g=17
--@assign id=34 abbr="Step" name="Step size"    l=0 h=127 manual=true g=18
--@assign id=35 abbr="Len"  name="Length"       l=0 h=127 manual=true g=19
--@assign id=36 abbr="CC"   name="CC number"    l=0 h=127 manual=true g=20
--@assign id=37 abbr="Chan" name="MIDI channel" l=0 h=127 manual=true g=21
--@assign id=38 abbr="Out"  name="Output port"  l=0 h=127 manual=true g=22
--@assign id=39 abbr="Trim" name="Tempo trim"   l=0 h=127 manual=true g=23
-- pages: Mod,Set

local DT = 20.1            -- real update period: firmware fires after > rate ms
local FULL = 16383
local C_ON, C_PLAY, C_GLIDE = 0, 50, 25   -- LED hue rotation (0-100)

-- Step values (page 1) and glide bit mask
local S = {0, 16, 32, 48, 64, 80, 96, 112, 127, 112, 96, 80, 64, 48, 32, 16}
local GL = 0

-- Settings (page 2, ids 33-39)
local SN = {"bpm", "div", "len", "cc", "ch", "out", "trim"}
local SV = {120, 4, 16, 74, 1, 0, 0}
local LO = {20, 1, 1, 0, 1, 0, -99}
local HI = {300, 8, 16, 127, 16, 15, 99}
local DIVS = {1, 2, 3, 4, 6, 8}
local DL = {"1/4", "1/8", "8T", "1/16", "D5", "16T", "D7", "1/32"}

local run, cur, cnt, K = false, 0, 0, 5   -- transport, step (1-16), tick in step, ticks/step
local last = -1                           -- last CC value sent
local title, shown                        -- pending / displayed header text

local function clamp(v, lo, hi)
  return v < lo and lo or v > hi and hi or v
end

local function glide(i) return GL >> (i - 1) & 1 == 1 end

local function setTitle()
  local s = (run and "MOD > " or "MOD | ") .. SV[1]
  if s ~= shown then
    page.resetTitle()                 -- title freeze workaround: set on next tick
    title, shown = s, s
  end
end

-- Pick an update rate of 20-40 ms so a step is exactly K ticks (as in Euclid).
local function timing()
  local ms = 60000 / (SV[1] * SV[2]) / (1 + SV[7] / 1000)
  local best, rate = 1e9, 20
  for k = -(-ms // 40), ms // 20 do
    local p = clamp((ms / k + 0.4) // 1, 20, 1000)
    local e = math.abs(k * (p + 0.1) - ms)
    if e < best then best, rate, K = e, p, k end
  end
  DT = rate + 0.1
  system.setUpdateRate(rate)
end

-- Ring (and label, when full) of step i, if page 1 is showing.
local function draw(i, full, pg)
  if (pg or controller.getPage()) ~= 1 then return end
  local g = glide(i)
  leds.updateByIndex(i, i > SV[3] and 0 or S[i] * FULL // 127,
    run and i == cur and C_PLAY or g and C_GLIDE or C_ON)
  if full then slots.update(i, (g and "~" or "") .. S[i]) end
end

local function drawAll(pg)
  pg = pg or controller.getPage()
  if pg == 1 then
    for i = 1, 16 do draw(i, true, pg) end
  elseif pg == 2 then
    for k = 1, 7 do
      local v = SV[k]
      leds.updateByIndex(k, (v - LO[k]) * FULL // (HI[k] - LO[k]), C_ON)
      slots.update(k, k == 1 and "" .. v or k == 2 and DL[v] or k == 3 and "L" .. v
        or k == 4 and (v < 100 and "CC" or "C") .. v or k == 5 and "Ch" .. v
        or k == 6 and (v == 0 and "All" or "O" .. v) or (v > 0 and "T+" or "T") .. v)
    end
  end
  setTitle()
end

local function send(v)
  if v ~= last then
    midi.sendCC(SV[6], SV[5] - 1, SV[4], v)
    last = v
  end
end

function system.update()
  if title then page.setTitle(title); title = nil end
  if not run then return end
  cnt = cnt + 1
  if cnt >= K or cur == 0 then        -- next step (always leave step 0 at once)
    cnt = 0
    local was = cur
    cur = cur % SV[3] + 1
    if was > 0 then draw(was) end
    draw(cur)
  end
  local v = S[cur]
  if glide(cur) then                  -- ramp toward the next step's value
    v = math.floor(v + (S[cur % SV[3] + 1] - v) * cnt / K + 0.5)
  end
  send(v)
end

-- Turn ids 1-16 set step values, 33-39 the settings; pushes 17-32 toggle
-- glide, 49 is play/stop.
function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or id < 1 or id > 39 or id > 16 and id < 33 then return end
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  if id > 32 then
    local k = id - 32
    local v = SV[k]
    if k == 2 then
      local i = 1
      while DIVS[i] < v do i = i + 1 end
      v = DIVS[clamp(i + (d > 0 and 1 or -1), 1, 6)]
    else
      v = clamp(v + ((k == 1 or k == 4) and d or d > 0 and 1 or -1), LO[k], HI[k])
    end
    SV[k] = v
    var.set(SN[k], v)
    if k == 4 or k == 5 or k == 6 then last = -1 end   -- resend to the new destination
    timing()
    drawAll(e.page)
    return
  end
  S[id] = clamp(S[id] + d, 0, 127)
  var.set("s" .. id, S[id])
  draw(id, true, e.page)
end

function controller.onEncoderPress(e)
  if e.id == 49 then
    run, cur, cnt = not run, 0, 0
    if run then cnt = K - 1 end       -- first update starts step 1
    drawAll()
    return
  end
  local i = e.id - 16
  if i < 1 or i > 16 then return end
  GL = GL ~ 1 << (i - 1)
  var.set("glide", GL)
  draw(i, true, e.page)
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
  local g = var.get
  for i = 1, 16 do
    var.register("s" .. i, "int", S[i])
    S[i] = clamp(g("s" .. i), 0, 127)
  end
  var.register("glide", "int", GL)
  GL = g("glide") & 0xFFFF
  for k = 1, 7 do
    var.register(SN[k], "int", SV[k])
    SV[k] = clamp(g(SN[k]), LO[k], HI[k])
  end
  last = -1
  timing()
end

function page.onVarChange()
  pull()
  drawAll()
end

function page.onInit()
  pull()
  for id = 1, 39 do
    if id < 17 or id > 32 then controller.set(id, {manual = true, v = 8192}) end
  end
  drawAll()
end
