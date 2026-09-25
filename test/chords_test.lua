-- Tests for chords.lua. Run from the repo root with a LUA_32BITS Lua, after
-- tools/make_chords.py has filled the data (it caches sets in build/chordsets):
--   lua test/chords_test.lua
local E = dofile("test/e16mock.lua")
local check = E.check

local SETS = {"cinematic", "chill_house", "gospel_soul", "neo_soul_minor", "lofi_rb_1",
  "indie_jazz", "detroit_techno", "lush_pads", "pop_piano", "impressionist", "sad_ballads"}

-- chord k (0-based) of a cached .chords file
local function source(set, k)
  for line in io.lines("build/chordsets/" .. set .. ".chords") do
    local i, notes = line:match("^%s*(%d+):%s*([%d,%s]+)")
    if i and tonumber(i) == k then
      local t = {}
      for n in notes:gmatch("%d+") do t[#t + 1] = tonumber(n) end
      table.sort(t)
      return t
    end
  end
end

local function pad(pg, i)
  E.page = pg
  controller.onEncoderPress{id = 16 + i, index = i, page = pg, value = 8192, scaled = 64}
end
-- turn setting k by n detents (one step each)
local function set(k, n)
  E.page = 12
  for _ = 1, math.abs(n) do
    controller.onEncoderTurn{id = 32 + k, index = k, page = 12, increment = n > 0 and 1 or -1,
      value = 8192, scaled = 64, is_held = false}
  end
end
local function ons(from)
  local r = {}
  for i = from or 1, #E.sent do
    local m = E.sent[i]
    if m.st & 0xF0 == 0x90 and m.d2 > 0 then r[#r + 1] = m end
  end
  return r
end
local function notes(list)
  local t = {}
  for _, m in ipairs(list) do t[#t + 1] = m.d1 end
  return table.concat(t, ",")
end

E.load("chords.lua")
E.run(100)
check(E.title == "Cinematic", "page 1 title is the set name (" .. E.title .. ")")
check(E.labels[1] ~= nil and E.labels[16] ~= nil, "page 1 labels: " .. table.concat(E.labels, " ", 1, 16))

-- every pad on every page plays exactly the source voicing
local bad = 0
for pg = 1, 11 do
  for i = 1, 16 do
    E.sent = {}
    pad(pg, i)
    E.run(40)
    local want = source(SETS[pg], i - 1)
    local got = notes(ons())
    if want and got ~= table.concat(want, ",") then
      bad = bad + 1
      if bad < 4 then print(("  page %d pad %d: got %s want %s"):format(pg, i, got, table.concat(want, ","))) end
    end
    pad(pg, i)                        -- Hold (default): same pad again stops
  end
end
check(bad == 0, "all 176 pads play their source chord")

-- labels fit and titles follow pages
local titles = {}
for pg = 1, 11 do E.show(pg); E.run(60); titles[#titles + 1] = E.title end
check(titles[3] == "Gospel Soul" and titles[11] == "Sad Ballads", "titles per page: " .. table.concat(titles, ", "))
E.show(1); E.run(60)

-- hold: a new pad releases the previous chord first
E.sent = {}
pad(1, 1); E.run(40)
local first = #E.sent
pad(1, 2); E.run(40)
local offs = 0
for i = first + 1, #E.sent do
  if E.sent[i].d2 == 0 then offs = offs + 1 end
end
check(offs == first, "switching pads releases all notes of the previous chord (" .. offs .. "/" .. first .. ")")
check(E.rings[2].c == 50 and E.rings[1].c == 0, "ring lights on the sounding pad only")
pad(1, 2)
check(E.rings[2].c == 0, "pushing the sounding pad again stops it (hold)")

-- settings page
E.show(12); E.run(60)
check(E.title == "Chord settings", "settings title")
check(E.labels[1] == "T0" and E.labels[3] == "V100" and E.labels[4] == "Hold" and E.labels[6] == "Up",
  "settings labels: " .. table.concat(E.labels, " ", 1, 8))

-- gate 0.5 s
set(4, 5)
check(E.labels[4] == "0.5s", "gate 0.5 s label")
E.sent = {}
pad(1, 1)
E.run(300)
check(#E.sent > 0 and E.sent[#E.sent].d2 > 0, "notes still on at 300 ms")
E.run(300)
check(E.sent[#E.sent].d2 == 0, "notes released after the 0.5 s gate")
set(4, -5)

-- strum 50 ms, up then down
set(5, 5)
E.sent = {}
pad(1, 1)
E.run(600)
local s = ons()
local spaced = #s > 2
for i = 2, #s do if s[i].t - s[i - 1].t < 40 or s[i].d1 < s[i - 1].d1 then spaced = false end end
check(spaced, "strum up: notes rise, ~50 ms apart (" .. notes(s) .. ")")
pad(1, 1)
set(6, 1)
check(E.labels[6] == "Down", "direction Down")
E.sent = {}
pad(1, 1)
E.run(600)
s = ons()
local down = #s > 2
for i = 2, #s do if s[i].d1 > s[i - 1].d1 then down = false end end
check(down, "strum down: notes fall (" .. notes(s) .. ")")
pad(1, 1)
set(6, -1); set(5, -5)

-- transpose shifts notes and chord names
local before = notes((function() E.sent = {}; pad(1, 1); E.run(40); local r = ons(); pad(1, 1); return r end)())
E.show(1)
local l1 = E.labels[1]
set(1, 2)
E.show(1)
E.sent = {}; pad(1, 1); E.run(40)
local after = ons()
pad(1, 1)
check(after[1].d1 == tonumber(before:match("^%d+")) + 2, "transpose +2 moves notes up 2")
check(E.labels[1] ~= l1, "chord names follow transpose (" .. l1 .. " -> " .. E.labels[1] .. ")")
set(1, -2)

-- octave, channel, panic
set(2, 1)
E.sent = {}; pad(1, 1); E.run(40)
check(ons()[1].d1 == tonumber(before:match("^%d+")) + 12, "octave +1")
set(2, -1)
set(7, 1)                             -- channel 2: releases the sounding chord first
E.sent = {}; pad(1, 3); E.run(40)
check(ons()[1].st == 0x91, "channel 2")
E.page = 12
controller.onEncoderPress{id = 49, index = 1, page = 12, value = 8192, scaled = 64}
local cc = E.msgs(0xB1, 123)
check(#cc == 1, "panic sends CC 123 and note-offs")
set(7, -1)

-- persistence
set(3, -20)
E.load("chords.lua")
E.show(12)
check(E.labels[3] == "V80", "settings persist across reload (" .. E.labels[3] .. ")")

-- ignores foreign events
controller.onEncoderTurn{id = 255, index = 1, page = 3, increment = 1, value = 0, scaled = 0, is_held = false}
controller.onEncoderPress{id = 255, index = 1, page = 3, value = 0, scaled = 0}
check(true, "ignores id 255 events")

E.done()
