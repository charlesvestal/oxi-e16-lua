-- LFO: 16 LFOs sending MIDI CC, each on its own channel and CC number, for the
-- OXI E16 (firmware >= 1.2.0). A modulation bank across several synths.
--
-- Pages 1-4: four LFOs per page, one per row (page 1 = LFO 1-4 ... page 4 = LFO 13-16).
--   turn:  Shape (Sin Tri SawU SawD Sqr S&H) | Rate | Depth -100..+100 % | Center 0-127
--   push:  on/off | Sync/Free | freeze | Dest
--   Rate is free (20 s .. 6.4 Hz; labels "2.5s" = period, "1.0H" = Hz) or synced
--   to the tempo (8 bars .. 1/32, with triplets); pushing Rate toggles, keeping
--   about the same speed. Synced LFOs follow one beat counter, so they stay
--   locked together.
--   Dest flips the row's first two encoders to its MIDI channel and CC number
--   (labels "Ch3", "CC74"); push it again to go back. A destination (or output
--   port) left behind is sent the center value.
--   The Center ring shows the live output. An LFO that is off sends its center
--   value when it is switched off or its Center is turned (a plain CC knob).
-- Page 5, settings: 1 output port (0 = all), push = restart all (realigns synced
--   LFOs to the downbeat) | 2 BPM | 3 push = all off.
--
-- Defaults: only LFO 1 runs; page p sends on channel p, rows on CC 74, 71, 1, 10.
-- The header shows the page's LFOs and how many run in total ("LFO 1-4 3on").
-- Settings persist in scene variables a1-a16 (shape, rate, depth, center),
-- b1-b8 (CC, channel, on; two LFOs each), cfg (output, BPM) and ver: 26 of 32 slots.
-- A scene's variables outlive script changes, so a new layout version clears them.
--
-- No MIDI clock reaches Lua (firmware 1.2), so the tempo comes from BPM; if a
-- clock callback appears, it only has to drive `beat`.

--@assign id=1  abbr="Shp" name="Row 1 Shape / Channel" l=0 h=127 manual=true g=1
--@assign id=17 abbr="Shp" name="Row 1 On/Off"    p=true g=1
--@assign id=2  abbr="Rate" name="Row 1 Rate / CC" l=0 h=127 manual=true g=2
--@assign id=18 abbr="Rate" name="Row 1 Sync/Free" p=true g=2
--@assign id=3  abbr="Dep" name="Row 1 Depth"      l=0 h=127 manual=true g=3
--@assign id=19 abbr="Dep" name="Row 1 Freeze"     p=true g=3
--@assign id=4  abbr="Ctr" name="Row 1 Center"     l=0 h=127 manual=true g=4
--@assign id=20 abbr="Ctr" name="Row 1 Dest"       p=true g=4
--@assign id=5  abbr="Shp" name="Row 2 Shape / Channel" l=0 h=127 manual=true g=5
--@assign id=21 abbr="Shp" name="Row 2 On/Off"    p=true g=5
--@assign id=6  abbr="Rate" name="Row 2 Rate / CC" l=0 h=127 manual=true g=6
--@assign id=22 abbr="Rate" name="Row 2 Sync/Free" p=true g=6
--@assign id=7  abbr="Dep" name="Row 2 Depth"      l=0 h=127 manual=true g=7
--@assign id=23 abbr="Dep" name="Row 2 Freeze"     p=true g=7
--@assign id=8  abbr="Ctr" name="Row 2 Center"     l=0 h=127 manual=true g=8
--@assign id=24 abbr="Ctr" name="Row 2 Dest"       p=true g=8
--@assign id=9  abbr="Shp" name="Row 3 Shape / Channel" l=0 h=127 manual=true g=9
--@assign id=25 abbr="Shp" name="Row 3 On/Off"    p=true g=9
--@assign id=10 abbr="Rate" name="Row 3 Rate / CC" l=0 h=127 manual=true g=10
--@assign id=26 abbr="Rate" name="Row 3 Sync/Free" p=true g=10
--@assign id=11 abbr="Dep" name="Row 3 Depth"      l=0 h=127 manual=true g=11
--@assign id=27 abbr="Dep" name="Row 3 Freeze"     p=true g=11
--@assign id=12 abbr="Ctr" name="Row 3 Center"     l=0 h=127 manual=true g=12
--@assign id=28 abbr="Ctr" name="Row 3 Dest"       p=true g=12
--@assign id=13 abbr="Shp" name="Row 4 Shape / Channel" l=0 h=127 manual=true g=13
--@assign id=29 abbr="Shp" name="Row 4 On/Off"    p=true g=13
--@assign id=14 abbr="Rate" name="Row 4 Rate / CC" l=0 h=127 manual=true g=14
--@assign id=30 abbr="Rate" name="Row 4 Sync/Free" p=true g=14
--@assign id=15 abbr="Dep" name="Row 4 Depth"      l=0 h=127 manual=true g=15
--@assign id=31 abbr="Dep" name="Row 4 Freeze"     p=true g=15
--@assign id=16 abbr="Ctr" name="Row 4 Center"     l=0 h=127 manual=true g=16
--@assign id=32 abbr="Ctr" name="Row 4 Dest"       p=true g=16
--@assign id=33 abbr="Out" name="Output port"     l=0 h=127 manual=true g=17
--@assign id=49 abbr="Out" name="Restart all"     p=true g=17
--@assign id=34 abbr="BPM" name="Tempo"           l=0 h=127 manual=true g=18
--@assign id=51 abbr="Stop" name="All off"        p=true g=19
-- pages: LFO1,LFO2,LFO3,LFO4,Set

local N, PAGES, SETP = 16, 4, 5
local DT = 20.1            -- real update period: firmware fires after > 20 ms
local FULL = 16383
local C_ON, C_OFF, C_FRZ, C_DEST, C_SYNC = 0, 75, 50, 25, 35   -- LED hue rotation (0-100)
local SHN = {"Sin", "Tri", "SawU", "SawD", "Sqr", "S&H"}
-- Sync divisions: beats per cycle, and labels. Rate values 85-96 select them.
local DIVB = {32, 16, 8, 4, 2, 1, 2 / 3, 1 / 2, 1 / 3, 1 / 4, 1 / 6, 1 / 8}
local DIVL = {"8Br", "4Br", "2Br", "1Br", "1/2", "1/4", "4T", "1/8", "8T", "1/16", "16T", "1/32"}

-- Per LFO: shape 1-6, rate (0-84 free, 85-96 synced), depth -100..100 (even),
-- center, CC, channel 1-16, on, freeze, Dest view, phase 0-1, S&H value, last CC sent.
local SH, RT, DP, CT, CC, CH, ON = {}, {}, {}, {}, {}, {}, {}
local FZ, DV, PH, RND, LAST = {}, {}, {}, {}, {}
local DSH, DRT, DCC = {1, 2, 5, 6}, {36, 24, 48, 30}, {74, 71, 1, 10}   -- per-row defaults
for t = 1, N do
  local r = (t - 1) % 4 + 1
  SH[t], RT[t], DP[t], CT[t] = DSH[r], DRT[r], 50, 64
  CC[t], CH[t], ON[t] = DCC[r], (t + 3) // 4, t == 1 and 1 or 0
  FZ[t], DV[t], PH[t], RND[t], LAST[t] = 0, 0, 0, math.random() * 2 - 1, -1
end
local out, bpm, beat = 0, 120, 0   -- output port, tempo, beats since restart (mod 32)
local title, shown

local function clamp(v, lo, hi)
  return v < lo and lo or v > hi and hi or v
end

-- Rate of LFO t in Hz.
local function hz(t)
  local r = RT[t]
  return r > 84 and bpm / 60 / DIVB[r - 84] or 0.05 * 2 ^ (r / 12)
end

-- Packing (each value < 2^24): a = shape-1 | rate << 3 | (depth+100)/2 << 10 | center << 17,
-- and 12 bits per LFO in b: CC | channel-1 << 7 | on << 11 (odd LFO low, even LFO high).
local function packA(t) return SH[t] - 1 | RT[t] << 3 | (DP[t] + 100) // 2 << 10 | CT[t] << 17 end
local function part(t) return CC[t] | CH[t] - 1 << 7 | ON[t] << 11 end

local function save(t)
  local j = (t + 1) // 2
  var.set("a" .. t, packA(t))
  var.set("b" .. j, part(j * 2 - 1) | part(j * 2) << 12)
end

-- Current output of LFO t (0-127); an LFO that is off outputs its center.
local function value(t)
  if ON[t] == 0 then return CT[t] end
  local s, p = SH[t], PH[t]
  local w = s == 1 and math.sin(p * 6.2831853) or s == 2 and 1 - 4 * math.abs(p - 0.5)
    or s == 3 and 2 * p - 1 or s == 4 and 1 - 2 * p or s == 5 and (p < 0.5 and 1 or -1) or RND[t]
  return clamp(math.floor(CT[t] + DP[t] * 0.635 * w + 0.5), 0, 127)
end

local function send(t, v)
  midi.sendCC(out, CH[t] - 1, CC[t], v)
  LAST[t] = v
end

-- Draw LFO t (if its page shows): the live Center ring always, the rest when full.
local function draw(t, full, pg)
  if (pg or controller.getPage()) ~= (t + 3) // 4 then return end
  local b = (t - 1) % 4 * 4
  local c = ON[t] == 0 and C_OFF or FZ[t] > 0 and C_FRZ or C_ON
  local set, lab = leds.updateByIndex, slots.update
  set(b + 4, value(t) * FULL // 127, c)
  if not full then return end
  local d, r = DP[t], RT[t]
  if DV[t] > 0 then
    set(b + 1, (CH[t] - 1) * FULL // 15, C_DEST)
    set(b + 2, CC[t] * FULL // 127, C_DEST)
    lab(b + 1, "Ch" .. CH[t])
    lab(b + 2, (CC[t] < 100 and "CC" or "C") .. CC[t])
  else
    set(b + 1, (SH[t] - 1) * FULL // 5, c)
    lab(b + 1, SHN[SH[t]])
    if r > 84 then
      set(b + 2, (r - 85) * FULL // 11, C_SYNC)
      lab(b + 2, DIVL[r - 84])
    else
      -- whole-number formatting only: the device's printf may not support %f
      local h = hz(t)
      local x = math.floor((h >= 1 and h or 1 / h) * 10 + 0.5)   -- tenths of Hz or s
      set(b + 2, r * FULL // 84, c)
      lab(b + 2, h < 1 and x >= 100 and (x + 5) // 10 .. "s" or x // 10 .. "." .. x % 10 .. (h < 1 and "s" or "H"))
    end
  end
  set(b + 3, math.abs(d) * FULL // 100, c)
  lab(b + 3, (d > 0 and "+" or "") .. d)
  lab(b + 4, "" .. CT[t])
end

local function drawAll(pg)
  pg = pg or controller.getPage()
  if pg <= PAGES then
    for r = 1, 4 do draw(pg * 4 - 4 + r, true, pg) end
  elseif pg == SETP then
    leds.updateByIndex(1, out * FULL // 15, C_ON)
    slots.update(1, out == 0 and "All" or "O" .. out)
    leds.updateByIndex(2, (bpm - 20) * FULL // 280, C_SYNC)
    slots.update(2, "" .. bpm)
    slots.update(3, "Stop")
  end
  local n = 0
  for t = 1, N do n = n + ON[t] end
  local s = pg <= PAGES and "LFO " .. pg * 4 - 3 .. "-" .. pg * 4 .. " " .. n .. "on" or "LFO settings"
  if s ~= shown then
    page.resetTitle()                 -- title freeze workaround: set on next tick
    title, shown = s, s
  end
end

local function update()
  if title then page.setTitle(title); title = nil end
  beat = (beat + DT / 1000 * bpm / 60) % 32
  local pg = controller.getPage()
  for t = 1, N do
    if ON[t] > 0 then
      if FZ[t] == 0 then
        local r, p = RT[t], nil
        if r > 84 then
          p = beat / DIVB[r - 84] % 1       -- synced: locked to the beat counter
        else
          p = (PH[t] + hz(t) * DT / 1000) % 1
        end
        if p < PH[t] then RND[t] = math.random() * 2 - 1 end   -- new cycle: new S&H value
        PH[t] = p
      end
      local v = value(t)
      if v ~= LAST[t] then
        send(t, v)
        draw(t, false, pg)
      end
    end
  end
end

-- An error in update would stop the E16's updates for good: catch it and show it.
function system.update()
  local ok, e = pcall(update)
  if not ok then
    shown = nil
    page.setTitle(("ERR " .. tostring(e):gsub("^.-:%d+: ", "")):sub(1, 15))
  end
end

-- Turn ids 1-16 edit the LFOs of the current page (1-4); 33 output, 34 BPM.
function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or not (id == 33 or id == 34 or id >= 1 and id <= 16 and e.page <= PAGES) then return end
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  local s = d > 0 and 1 or -1
  if id > 32 then
    if id == 33 then
      local o = clamp(out + s, 0, 15)
      if o ~= out then
        for t = 1, N do
          if ON[t] > 0 then send(t, CT[t]) end   -- leave the old port at the centers
          LAST[t] = -1                  -- and resend everything to the new one
        end
        out = o
      end
    else
      bpm = clamp(bpm + d, 20, 300)
    end
    var.set("cfg", out | bpm << 4)
    drawAll(e.page)
    return
  end
  local t, k = e.page * 4 - 4 + (id + 3) // 4, (id - 1) % 4 + 1
  local ch, cc = CH[t], CC[t]
  if k == 1 then
    if DV[t] > 0 then CH[t] = clamp(CH[t] + s, 1, 16) else SH[t] = clamp(SH[t] + s, 1, 6) end
  elseif k == 2 then
    if DV[t] > 0 then CC[t] = clamp(CC[t] + d, 0, 127)
    elseif RT[t] > 84 then RT[t] = clamp(RT[t] + s, 85, 96)
    else RT[t] = clamp(RT[t] + s, 0, 84) end
  elseif k == 3 then
    DP[t] = clamp(DP[t] + d * 2, -100, 100)
  else
    CT[t] = clamp(CT[t] + d, 0, 127)
  end
  if ch ~= CH[t] or cc ~= CC[t] then  -- new destination: old one back to center, resend
    midi.sendCC(out, ch - 1, cc, CT[t])
    LAST[t] = -1
  end
  save(t)
  if ON[t] == 0 and k == 4 then send(t, CT[t]) end
  draw(t, true, e.page)
end

-- Toggle LFO t between free and synced, keeping about the same speed.
local function toggleSync(t)
  local h = hz(t)
  if RT[t] > 84 then
    RT[t] = clamp(math.floor(12 * math.log(h / 0.05, 2) + 0.5), 0, 84)
  else
    local best, bi = 1e9, 1
    for i = 1, #DIVB do
      local e = math.abs(math.log(bpm / 60 / DIVB[i] / h))
      if e < best then best, bi = e, i end
    end
    RT[t] = 84 + bi
  end
end

-- Pushes 17-32: on/off, Sync/Free, freeze, Dest per row; 49 restart all, 51 all off.
function controller.onEncoderPress(e)
  local id = e.id
  if id == 49 then
    beat = 0
    for t = 1, N do PH[t] = 0 end
  elseif id == 51 then
    for t = 1, N do
      if ON[t] > 0 then
        ON[t] = 0
        send(t, CT[t])                  -- back to the center value
        save(t)
      end
    end
  elseif id >= 17 and id <= 32 and e.page <= PAGES then
    local t, k = e.page * 4 - 4 + (id - 13) // 4, (id - 17) % 4 + 1
    if k == 1 then
      ON[t] = 1 - ON[t]
      RND[t] = math.random() * 2 - 1    -- S&H starts on a fresh value
      save(t)
      send(t, value(t))                 -- off: back to the center value
    elseif k == 2 then
      toggleSync(t)
      save(t)
    elseif k == 3 then
      FZ[t] = 1 - FZ[t]
    else
      DV[t] = 1 - DV[t]
    end
  else
    return
  end
  drawAll(e.page)
end

function page.onPageChange(prev, curr)
  if prev <= SETP then
    for i = 1, 16 do
      leds.reset(i)
      slots.reset(i)
    end
  end
  drawAll(curr)                       -- getPage() may not report curr yet
end

local VER = 2                         -- bump when the variable layout changes

local function pull()
  local g = var.get
  if g("ver") ~= VER then               -- old or foreign variables: start clean
    var.deleteAll()
    var.register("ver", "int", VER)
  end
  for t = 1, N do
    var.register("a" .. t, "int", packA(t))
    local v = g("a" .. t) or packA(t)
    SH[t], RT[t] = clamp((v & 7) + 1, 1, 6), clamp(v >> 3 & 127, 0, 96)
    DP[t], CT[t] = clamp((v >> 10 & 127) * 2 - 100, -100, 100), v >> 17 & 127
  end
  for j = 1, N // 2 do
    var.register("b" .. j, "int", part(j * 2 - 1) | part(j * 2) << 12)
    local v = g("b" .. j) or part(j * 2 - 1) | part(j * 2) << 12
    for t = j * 2 - 1, j * 2 do
      local q = t % 2 == 1 and v & 4095 or v >> 12 & 4095
      CC[t], CH[t], ON[t] = q & 127, (q >> 7 & 15) + 1, q >> 11 & 1
    end
  end
  var.register("cfg", "int", out | bpm << 4)
  local v = g("cfg") or out | bpm << 4
  out, bpm = clamp(v & 15, 0, 15), clamp(v >> 4, 20, 300)
  for t = 1, N do LAST[t] = -1 end
end

function page.onVarChange()
  pull()
  drawAll()
end

function page.onInit()
  pull()
  for id = 1, 34 do
    if id < 17 or id > 32 then controller.set(id, {manual = true, v = 8192}) end
  end
  system.setUpdateRate(20)
  drawAll()
end
