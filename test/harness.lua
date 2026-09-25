-- Desktop test harness: mocks the OXI E16 Lua API (firmware 1.2.0) and
-- exercises euclid.lua. Run with a Lua 5.4 built with LUA_32BITS=1 to match
-- the device's number types:  lua test/harness.lua euclid.lua

local script = arg[1] or "euclid.lua"
local fails = 0
local function check(ok, msg)
  if not ok then fails = fails + 1; print("FAIL: " .. msg) else print("ok   " .. msg) end
end

-- ------------------------------------------------------------------ mock API
local now = 0                  -- ms
local sent = {}                -- {t, out, cable, status, d1, d2}
local ledsState, slotState, titleText = {}, {}, ""
local store, types = {}, {}
local curPage = 1

midi = {
  sendMidi = function(o, c, s, a, b)
    assert(math.type(s) == "integer" and s >= 0x80 and s <= 0xFF, "bad status " .. tostring(s))
    assert(a >= 0 and a <= 127 and b >= 0 and b <= 127, "bad data byte")
    sent[#sent + 1] = {now, o, c, s, a, b}
  end,
  sendCC = function(o, c, cc, v) sent[#sent + 1] = {now, o, c, 0xB0 + c, cc, v, cc = cc} end, sendPC = function() end, sendSysex = function() end,
}
leds = {
  update = function(id, v, c)
    assert(id >= 0 and id <= 255, "led id"); assert(v >= 0 and v <= 16383, "led value " .. v)
    assert(c >= 0 and c <= 100, "led color " .. c)
    ledsState[id] = {v, c}
  end,
  updateByIndex = function(i, v, c)
    assert(i >= 1 and i <= 16, "led index"); assert(v >= 0 and v <= 16383, "led value " .. v)
    ledsState[i] = {v, c}
  end,
  reset = function(i) ledsState[i] = nil end,
  resetById = function() end,
}
slots = {
  update = function(i, s)
    assert(type(s) == "string", "label must be string")
    assert(#s <= 4, "label too long: '" .. s .. "'")
    slotState[i] = s
  end,
  reset = function(i) slotState[i] = nil end,
}
page = { setTitle = function(s) assert(#s <= 15, "title too long"); titleText = s end,
         resetTitle = function() end }
controller = { getPage = function() return curPage end,
               set = function() end, setByIndex = function() end, setControls = function() end }
var = {
  register = function(n, ty, d)
    assert(#n <= 16, "var name too long")
    if store[n] == nil then store[n] = d; types[n] = ty end
  end,
  get = function(n) return store[n] end,
  set = function(n, v) if store[n] ~= nil then store[n] = v end end,
  delete = function(n) store[n] = nil end,
  deleteAll = function() store = {} end,
}
local rate = 0
system = { setUpdateRate = function(ms) rate = (ms >= 20 and ms <= 1000) and ms or 0 end }

-- ------------------------------------------------------------------ load
local function load_script()
  -- mimic the device: a fresh VM each scene load (vars survive in `store`)
  sent = {}
  collectgarbage(); collectgarbage()
  local before = collectgarbage("count")
  dofile(script)
  page.onInit()
  collectgarbage(); collectgarbage()
  return (collectgarbage("count") - before) * 1024
end

local function run_ms(ms)
  local stop = now + ms
  -- firmware fires once MORE than `rate` ms passed on a 0.1 ms tick: 20.1 ms
  local period = rate + 0.1
  while now + period <= stop do
    now = now + period
    local ok, err = pcall(system.update)
    if not ok then rate = 0; error("update() raised (firmware would disable updates): " .. err) end
  end
end

local function turn(id, inc) controller.onEncoderTurn{id = id, index = id, page = 1, increment = inc, value = 0, scaled = 0, is_held = false} end
local function press(id) controller.onEncoderPress{id = id + 16, index = id, page = 1, value = 0, scaled = 0} end

local function noteOns(from, to, n)
  local r = {}
  for _, m in ipairs(sent) do
    if m[1] >= from and m[1] < to and m[4] & 0xF0 == 0x90 and m[6] > 0 and (not n or m[5] == n) then r[#r + 1] = m end
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

-- ------------------------------------------------------------------ tests
local heap = load_script()
print(string.format("script heap after init: %.0f bytes", heap))
check(heap < 32 * 1024, "heap after init (64-bit host; see e16host for device numbers)")
check(rate == 25, "update rate divides a 120 BPM 16th evenly (" .. rate .. " ms)")
run_ms(100)
check(titleText:match("^EUC heap %d+KB$") ~= nil and #titleText <= 15, "startup header shows heap ('" .. titleText .. "')")
run_ms(3000)
check(titleText == "EUC | 120", "title shows stopped + bpm ('" .. titleText .. "')")
check(slotState[1] == "L16" and slotState[2] == "P4" and slotState[3] == "R0" and slotState[4] == "C2",
  "labels for track 1: " .. tostring(slotState[1]) .. " " .. tostring(slotState[2]) .. " " .. tostring(slotState[3]) .. " " .. tostring(slotState[4]))
check(slotState[8] == "D2" and slotState[7] == "R+4", "track 2 labels (" .. tostring(slotState[7]) .. ", " .. tostring(slotState[8]) .. ")")

-- stopped: nothing plays
run_ms(1000)
check(#sent == 0, "no MIDI while stopped")

-- Pattern correctness for many (k, n), compared with reference Bjorklund
local allok = true
for n = 1, 32 do
  for k = 0, n do
    -- set track 1 to (k, n) by turning encoders
    while true do local before = slotState[1]; turn(1, -1); if slotState[1] == before then break end end -- len -> 1
    for _ = 2, n do turn(1, 1) end
    for _ = 1, 40 do turn(2, -1) end
    for _ = 1, k do turn(2, 1) end
    -- read the pattern straight from the note stream: run n steps at known tempo
    sent = {}
    local t0 = now
    press(3)  -- play
    run_ms(0) -- first step fires on press
    local stepms = 60000 / (120 * 4)
    run_ms(math.ceil(stepms * n) + 1)
    press(3)  -- stop
    local hits = {}
    for i = 1, n do hits[i] = 0 end
    local ons = noteOns(t0, now + 1, 36)
    -- map note times to steps using expected step times (quantized to 20 ms grid)
    local seen = {}
    for _, m in ipairs(ons) do
      local step = math.floor((m[1] - t0) / stepms + 0.5)
      if step < n and not seen[step] then seen[step] = true; hits[step + 1] = 1 end
    end
    if not isRotation(hits, bjorklund(k, n)) then
      allok = false
      print(("  mismatch k=%d n=%d got %s"):format(k, n, table.concat(hits)))
    end
  end
end
check(allok, "E(k,n) for all 0<=k<=n<=32 match Bjorklund (up to rotation)")

-- Tempo accuracy: 120 bpm, 16ths -> 125 ms steps; count over 60 s
for _ = 1, 40 do turn(1, -1) end
for _ = 1, 15 do turn(1, 1) end        -- len 16
for _ = 1, 40 do turn(2, 1) end        -- pulses = 16 (every step)
sent = {}
local t0 = now
press(3)
run_ms(60000)
press(3)
local n1 = #noteOns(t0, t0 + 60000, 36)
check(n1 >= 475 and n1 <= 481, "tempo within 1% at 120 BPM: " .. n1 .. " sixteenths/min (ideal 480)")
local ons, lo, hi = noteOns(t0, t0 + 60000, 36), 1e9, 0
for i = 2, #ons do
  local d = ons[i][1] - ons[i - 1][1]
  lo, hi = math.min(lo, d), math.max(hi, d)
end
check(hi - lo < 0.01, ("steps evenly spaced (%.2f-%.2f ms)"):format(lo, hi))
local cc123 = false
for _, m in ipairs(sent) do if m.cc == 123 then cc123 = true end end
check(cc123, "stop sends CC 123")

-- every note-on gets a matching note-off
local open = {}
for _, m in ipairs(sent) do
  if m[4] & 0xF0 == 0x90 then
    if m[6] > 0 then open[m[5]] = (open[m[5]] or 0) + 1 else open[m[5]] = (open[m[5]] or 0) - 1 end
  end
end
local hanging = 0
for _, c in pairs(open) do hanging = hanging + c end
check(hanging == 0, "no hanging notes after stop")
check(sent[1][4] == 0x99, "sends on channel 10 (status 0x99)")

-- mute
sent = {}
press(1)          -- mute track 1
check(slotState[1] == "MUTE", "mute label")
t0 = now
press(3); run_ms(2000); press(3)
check(#noteOns(t0, now + 1, 36) == 0, "muted track is silent")
check(#noteOns(t0, now + 1, 38) > 0, "other tracks still play")
press(1)

-- invert
for _ = 1, 40 do turn(2, -1) end; for _ = 1, 4 do turn(2, 1) end  -- 4 of 16
press(2)
check(slotState[2] == "i4", "invert label")
sent = {}; t0 = now
press(3); run_ms(math.ceil(125 * 16) + 1); press(3)
check(#noteOns(t0, now + 1, 36) == 12, "inverted E(4,16) plays 12 hits (got " .. #noteOns(t0, now + 1, 36) .. ")")
press(2)

-- rotation label/clamp
for _ = 1, 40 do turn(3, 1) end
check(slotState[3] == "R+15", "rotation clamps to len-1 (" .. slotState[3] .. ")")
for _ = 1, 80 do turn(3, -1) end
check(slotState[3] == "R-15", "rotation clamps to -(len-1) (" .. slotState[3] .. ")")
for _ = 1, 15 do turn(3, 1) end

-- note range and acceleration
for _ = 1, 30 do turn(4, 8) end
check(slotState[4] == "G9", "note clamps to 127 = G9 (" .. slotState[4] .. ")")
for _ = 1, 30 do turn(4, -8) end
check(slotState[4] == "C-1", "note clamps to 0 = C-1 (" .. slotState[4] .. ")")
for _ = 1, 36 do turn(4, 1) end

-- shrinking length clamps pulses
for _ = 1, 40 do turn(2, 1) end        -- pulses 16
for _ = 1, 8 do turn(1, -1) end        -- len 8
check(slotState[2] == "P8" and slotState[1] == "L8", "shrinking length clamps pulses")

-- bad user vars must not break update()
store.bpm, store.div, store.ch, store.gate = 0, 0, 99, -5
page.onVarChange("bpm")
local ok = pcall(function() press(3); run_ms(1000); press(3) end)
local lastNote
for _, m in ipairs(sent) do if m[4] & 0xF0 == 0x90 then lastNote = m end end
check(lastNote and lastNote[4] == 0x9F, "channel var clamped to 16")
check(ok and rate >= 20, "survives out-of-range scene vars")
store.bpm, store.div, store.ch, store.gate = 120, 4, 10, 60
page.onVarChange("bpm")

-- persistence: edits are saved after 1 s idle and restored on reload
turn(5, -1)                             -- track 2 len 15
turn(8, 2)                              -- track 2 note 40
run_ms(1100)
local heap2 = load_script()              -- fresh VM, same var store
check(slotState[5] == "L15" and slotState[8] == "E2", "state restored from vars after reload (" .. tostring(slotState[5]) .. ", " .. tostring(slotState[8]) .. ")")
check(heap2 < 20 * 1024, "heap after reload")

-- user edits a packed var from the device menu
store.L1, store.P1, store.N1 = 7, 3, 60
page.onVarChange("L1")
check(slotState[1] == "L7" and slotState[2] == "P3" and slotState[4] == "C4", "onVarChange reloads track")
store.bpm = 140; page.onVarChange("bpm"); run_ms(100)
check(titleText == "EUC | 140", "title follows bpm var")

-- page switching hands LEDs/labels back and restores them
-- playhead ring moves while playing (physical ring 1 = track 1 length)
press(3)
local seen = {}
for _ = 1, 8 do run_ms(125); seen[ledsState[1][1]] = true end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct >= 4, "playhead ring moves on the physical ring (" .. distinct .. " positions)")
press(3)

page.onPageChange(1, 3); curPage = 3
check(next(slotState) == nil and next(ledsState) == nil, "leaving page hands rings and labels back")
press(3); run_ms(500)
check(next(slotState) == nil and next(ledsState) == nil, "no drawing on another page")

-- settings page (page 2): encoders 1-6 = ids 33-38, push id 49 = play/stop
local function sturn(k, inc) controller.onEncoderTurn{id = 32 + k, index = k, page = 2, increment = inc, value = 0, scaled = 0, is_held = false} end
curPage = 2; page.onPageChange(3, 2)
check(slotState[1] == "140" and slotState[2] == "1/16" and slotState[3] == "G60"
  and slotState[4] == "Ch10" and slotState[5] == "All" and slotState[6] == "T0",
  "settings labels: " .. table.concat({tostring(slotState[1]), tostring(slotState[2]), tostring(slotState[3]), tostring(slotState[4]), tostring(slotState[5]), tostring(slotState[6])}, " "))
sturn(1, 4); run_ms(100)
check(store.bpm == 144 and slotState[1] == "144" and titleText == "EUC > 144", "BPM encoder uses acceleration, updates var + title (" .. titleText .. ")")
sturn(1, -8); sturn(1, -8); sturn(1, -8); run_ms(100)
check(store.bpm == 120, "BPM back to 120")
sturn(2, 1)
check(store.div == 6 and slotState[2] == "16T", "step size steps 1/16 -> 16T")
sturn(2, 8)
check(store.div == 8 and slotState[2] == "1/32", "step size clamps at 1/32")
sturn(2, -1); sturn(2, -1)
check(store.div == 4, "step size back to 1/16")
sturn(3, 8)
check(store.gate == 61, "gate moves 1 ms per detent regardless of speed (" .. store.gate .. ")")
for _ = 1, 3000 do sturn(3, 1) end
check(store.gate == 990 and slotState[3] == "G990", "gate clamps to 990")
store.gate = 60; page.onVarChange("gate")
sturn(4, 1)
check(store.ch == 11 and slotState[4] == "Ch11", "channel encoder")
sturn(4, -1)
sturn(5, 1)
check(store.out == 1 and slotState[5] == "O1", "output encoder")
sturn(5, -1)
check(slotState[5] == "All", "output 0 shows All")
sturn(6, 1); sturn(6, 1)
check(store.trim == 2 and slotState[6] == "T+2", "trim encoder")
sturn(6, -1); sturn(6, -1)
controller.onEncoderPress{id = 49, index = 1, page = 2, value = 0, scaled = 0}
run_ms(100)
check(titleText == "EUC | 120", "settings push stops playback (" .. titleText .. ")")
controller.onEncoderPress{id = 49, index = 1, page = 2, value = 0, scaled = 0}
run_ms(100)
check(titleText == "EUC > 120", "settings push starts playback")
check(slotState[1] == "120", "settings push leaves pattern page labels alone")
curPage = 1; page.onPageChange(2, 1)
check(slotState[1] == "L7", "returning to page redraws")
press(3)

-- non-physical value updates (recorder/random/group) arrive with increment 0
controller.onEncoderTurn{id = 1, index = 1, page = 1, increment = 0, value = 0, scaled = 0, is_held = false}
controller.onEncoderTurn{id = 255, index = 9, page = 1, increment = 1, value = 0, scaled = 0, is_held = false}
check(slotState[1] == "L7", "ignores increment-0 and id-255 turn events (" .. slotState[1] .. ")")

-- out-of-range edits from the var menu are clamped
store.P1, store.R1, store.N1 = 99, -99, 300
page.onVarChange("P1")
check(slotState[2] == "P7" and slotState[3] == "R-6" and slotState[4] == "G9", "var menu values clamped")
check(store.P1 == 7, "clamped value written back to the var")

print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
