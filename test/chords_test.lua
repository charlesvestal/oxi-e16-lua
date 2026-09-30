-- Tests for chords.lua. Run from the repo root with a LUA_32BITS Lua, after
-- tools/chordgen/build.py has built the sets into build/chordgen/sets:
--   lua test/chords_test.lua [SCRIPT DIR SET...]
-- With arguments, SCRIPT is tested against the sets DIR/SET.chords, one per page.
local E = dofile("test/e16mock.lua")
local check = E.check

local SCRIPT, DIR = arg[1] or "chords.lua", arg[2] or "build/chordgen/sets"
local SETS = {"cinematic", "chill_house", "gospel_soul", "neo_soul", "lofi_rb",
  "indie_jazz", "detroit", "lush_pads", "pop_piano", "impressionist", "sad_ballads"}
if arg[3] then SETS = {table.unpack(arg, 3)} end

-- chord k (0-based) of a cached .chords file
local function source(set, k)
  for line in io.lines(DIR .. "/" .. set .. ".chords") do
    local i, notes = line:match("^%s*(%d+):%s*([%d,%s]+)")
    if i and tonumber(i) == k then
      local t = {}
      for n in notes:gmatch("%d+") do t[#t + 1] = tonumber(n) end
      table.sort(t)
      return t
    end
  end
end

-- a set's title as chords.lua shows it (Name: line, 15 characters)
local function title(set)
  for line in io.lines(DIR .. "/" .. set .. ".chords") do
    local t = line:match("^%s*Name:%s*(.-)%s*$")
    if t then return t:sub(1, 15) end
  end
  return set:sub(1, 15)
end

local function pad(pg, i)
  E.page = pg
  controller.onEncoderPress{id = 16 + i, index = i, page = pg, value = 8192, scaled = 64}
end
local function lift(pg, i, held)
  controller.onEncoderRelease{id = 16 + i, index = i, page = pg, value = 8192, scaled = 64, held_ms = held or 100}
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

E.load(SCRIPT)
E.run(100)
check(E.store.gate == -1 and E.rate == 10, "default gate is Held; 10 ms updates")
E.store.gate = 0; page.onVarChange("gate")  -- most tests below use Ltch
check(E.title == title(SETS[1]), "page 1 title is the set name (" .. E.title .. ")")
check(E.labels[1] ~= nil and E.labels[16] ~= nil, "page 1 labels: " .. table.concat(E.labels, " ", 1, 16))

-- every pad on every page plays exactly the source voicing
local bad = 0
for pg = 1, #SETS do
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
check(bad == 0, ("all %d pads play their source chord"):format(16 * #SETS))

-- labels fit and titles follow pages
local titles = {}
for pg = 1, #SETS do E.show(pg); E.run(60); titles[#titles + 1] = E.title end
local want = {}
for pg = 1, #SETS do want[pg] = title(SETS[pg]) end
check(table.concat(titles, ",") == table.concat(want, ","), "titles per page: " .. table.concat(titles, ", "))
E.show(1); E.run(60)

-- latch: a new pad releases the previous chord first
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
check(E.rings[2].c == 0, "pushing the sounding pad again stops it (latch)")

-- settings page
E.show(12); E.run(60)
check(E.title == "Chord settings", "settings title")
check(E.labels[1] == "T0" and E.labels[3] == "V100" and E.labels[4] == "Ltch" and E.labels[6] == "Up",
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
controller.onEncoderPress{id = 57, index = 9, page = 12, value = 8192, scaled = 64}
local cc = E.msgs(0xB1, 123)
check(#cc == 1, "panic sends CC 123 and note-offs")
set(7, -1)

-- persistence
set(3, -20)
E.load(SCRIPT)
E.show(12)
check(E.labels[3] == "V80", "settings persist across reload (" .. E.labels[3] .. ")")

-- length (settings encoder 4): Held, Ltch, 0.1-4 s
local function offs()                         -- note-off is sent as note-on with velocity 0
  local n = 0
  for _, m in ipairs(E.sent) do if m.st & 0xF0 == 0x90 and m.d2 == 0 then n = n + 1 end end
  return n
end
set(4, -40)
check(E.labels[4] == "Held", "length bottoms out at Held (" .. E.labels[4] .. ")")
set(4, 1)
check(E.labels[4] == "Ltch", "then Ltch (" .. E.labels[4] .. ")")
set(4, 5)
E.sent = {}; pad(1, 2); E.run(300)
local on = #ons()
E.run(400)
check(on > 0 and offs() == on, "a 0.5 s length releases the chord (" .. on .. " on, " .. offs() .. " off)")
set(4, -5)
E.sent = {}; pad(1, 3); E.run(2000)
check(#ons() > 0 and offs() == 0, "Ltch keeps the chord sounding")
set(4, 3)
E.run(400)
check(offs() == #ons(), "turning up from Ltch releases the sounding chord")
set(4, -3)

-- Held: the chord sounds from push to release
set(4, -1); E.show(1)
check(E.store.gate == -1, "Held")
E.sent = {}; pad(1, 4); E.run(1500)
check(#ons() > 0 and offs() == 0, "Held: sounding while the pad is down")
lift(1, 4, 1500)
check(offs() == #ons() and E.rings[4].c == 0, "Held: release stops the chord and its ring")
E.sent = {}; pad(1, 5); E.run(20)
local first = #ons()
lift(1, 5, 20); E.run(500)
check(first > 0 and offs() == #ons(), "a quick tap plays and releases")
set(5, 5)                                     -- strum 50 ms: release mid-strum
E.show(1)
E.sent = {}; pad(1, 6); E.run(60); lift(1, 6, 60); E.run(1000)
check(#ons() >= 1 and #ons() < 4 and offs() == #ons(), "releasing mid-strum stops the rest (" .. #ons() .. " played)")
set(5, -5)
E.show(1)
E.sent = {}
pad(1, 7); E.run(100); pad(1, 8); E.run(100)  -- roll onto a second pad
lift(1, 7, 200)
check(offs() > 0 and E.rings[8].c ~= 0, "releasing an older pad leaves the newer chord sounding")
lift(1, 8, 100)
check(offs() == #ons(), "releasing the sounding pad stops it")
E.sent = {}; pad(12, 1); lift(12, 1)          -- settings-page push: no pad
check(true, "releases on the settings page are ignored")

-- editing: turn = root, hold + turn = chord type
local IVS = {"047", "037", "036", "048", "027", "057", "0479", "0379", "047A", "047B", "037A", "037B", "036A",
  "0369", "057A", "0247", "0237", "02479", "02379", "0247A", "0247B", "0237A", "0257A", "02457A", "02357A",
  "02457B", "02479A", "02379A", "02479B", "0147A", "0347A", "0467B", "0137A", "07"}
local function eturn(i, n, root)                -- chord type (held), or root (root = true)
  local held = not root
  if held then pad(1, i) end
  for _ = 1, math.abs(n) do
    controller.onEncoderTurn{id = i, index = i, page = 1, increment = n > 0 and 4 or -4, value = 8192, scaled = 64, is_held = false}
  end
  if held then lift(1, i) end
end
local function playNotes(i)
  E.sent = {}; pad(1, i); E.run(30); lift(1, i); E.run(20)
  local t = {}
  for _, m in ipairs(ons()) do t[#t + 1] = m.d1 end
  table.sort(t)
  return t
end
set(4, -40); set(5, -40); set(1, -40); set(1, 12); set(2, -10); set(2, 2)   -- Held, no strum, T0, Oc0
E.show(1); E.run(30)
local origLabel, origNotes = E.labels[1], table.concat(playNotes(1), ",")
eturn(1, 1)
check(E.labels[1] ~= origLabel and next(E.store.e or store.data.e) ~= nil, "turning a pad changes its type (" .. origLabel .. " -> " .. E.labels[1] .. ")")
eturn(1, -1)
check(E.labels[1] == origLabel and next(store.data.e) == nil and table.concat(playNotes(1), ",") == origNotes,
  "turning back restores the original and its hand voicing")
-- every type: the bass is the root, the pitch classes are the type's, all in range
local bass0 = playNotes(1)[1]
local okT, why = true, ""
for q = 1, #IVS do
  eturn(1, 1)
  local n = playNotes(1)
  local root = n[1] % 12
  local got = {}
  local lab = E.labels[1]
  -- which type is it now? match the pitch classes against the table
  for _, v in ipairs(n) do got[(v - root) % 12] = true end
  local match = false
  for _, iv in ipairs(IVS) do
    local w = {}
    for c in iv:gmatch(".") do w[tonumber(c, 16)] = true end
    local same = true
    for k in pairs(w) do if not got[k] then same = false end end
    for k in pairs(got) do if not w[k] then same = false end end
    if same then match = true end
  end
  local edited = store.data.e[1] ~= nil      -- (the original, once per cycle, keeps its hand voicing)
  if not match or edited and (math.abs(n[1] - bass0) > 6 or n[#n] - n[2 > #n and 1 or 2] > 12 or #n < 2) then
    okT, why = false, lab .. " " .. table.concat(n, ",")
  end
end
check(okT, "every chord type voices its own notes, root in the bass near the original (" .. why .. ")")
check(E.labels[1] == origLabel and store.data.e[1] == nil, "a full cycle of types wraps back to the original")
-- root: a plain turn moves it a semitone per event (not per acceleration step)
local r0 = playNotes(2)[1]
eturn(2, 2, true)
local r2 = playNotes(2)
check((r2[1] - r0) % 12 == 2 and math.abs(r2[1] - r0) <= 6, "turn: root up 2 semitones (" .. r0 .. " -> " .. r2[1] .. ")")
-- turning plays nothing: a sounding chord keeps ringing, the next push plays the edit
set(4, 1); E.show(1)
E.sent = {}; pad(1, 3); E.run(50)
local n1 = #ons()
local before3 = {}
for _, m in ipairs(ons()) do before3[#before3 + 1] = m.d1 end
eturn(3, 1, true); E.run(500)
check(n1 > 0 and #ons() == n1 and offs() == 0 and E.rings[3].c ~= 0, "turning a sounding pad: no new notes, the chord keeps ringing")
pad(1, 3); E.run(20)                          -- Ltch: this push stops it
check(offs() == n1, "... and it's released normally")
E.sent = {}; pad(1, 3); E.run(50)
local after3 = {}
for _, m in ipairs(ons()) do after3[#after3 + 1] = m.d1 end
check(table.concat(after3, ",") ~= table.concat(before3, ","), "the next push plays the edited chord")
pad(1, 3); E.run(20)
set(4, -1); E.show(1)
E.sent = {}; pad(1, 4); E.run(30)
local n4 = #ons()
for _ = 1, 3 do                               -- turning while held (pad 4 is down): type
  controller.onEncoderTurn{id = 4, index = 4, page = 1, increment = 1, value = 8192, scaled = 64, is_held = false}
end
E.run(300)
check(#ons() == n4 and offs() == 0 and store.data.e[4] ~= nil and store.data.e[4] // 64 == (store.data.e[4] // 64),
  "hold + turn: the held chord keeps ringing, nothing new plays")
lift(1, 4)
check(offs() == n4, "letting go releases it")
-- edits persist across reload, labels included
local l2 = E.labels[2]
E.load(SCRIPT); E.run(30)
check(E.labels[2] == l2 and store.data.e[2] ~= nil, "edits persist across reload (" .. l2 .. ")")
-- the settings Reset ring shows how much is edited; holding Reset clears everything
E.show(12)
check(E.labels[9] == "Pnic" and E.labels[10] == "Rset", "Panic and Reset knobs")
E.press(58); E.release(58, 500)
check(next(store.data.e) ~= nil, "a short push on Reset does nothing")
E.press(58); E.release(58, 2100)
check(next(store.data.e) == nil, "holding Reset for 2 s clears all edits")
E.show(1)
check(E.labels[1] == origLabel, "labels back to the originals")
-- every pad edited still fits the 1 KiB store
for pg = 1, 11 do
  E.show(pg)
  for i = 1, 16 do
    E.page = pg
    controller.onEncoderTurn{id = i, index = i, page = pg, increment = 1, value = 8192, scaled = 64, is_held = false}
  end
end
local nE = 0
for _ in pairs(store.data.e) do nE = nE + 1 end
check(nE >= 170 and store.size() <= 1024, ("all pads edited: %d edits, store %d of 1024 bytes"):format(nE, store.size()))
E.load(SCRIPT)
E.show(12); E.press(58); E.release(58, 2100)

-- ignores foreign events
controller.onEncoderTurn{id = 255, index = 1, page = 3, increment = 1, value = 0, scaled = 0, is_held = false}
controller.onEncoderPress{id = 255, index = 1, page = 3, value = 0, scaled = 0}
check(true, "ignores id 255 events")

-- another script's variables in the slot (32 max) are cleared, not overflowed
E.store = {}
for i = 1, 31 do E.store["old" .. i] = 1 end
local okF = pcall(E.load, SCRIPT)
check(okF and E.store.old1 == nil and E.store.ver == 31, "foreign variables are cleared on load")

E.done()
