-- Mock of the OXI E16 Lua API (v1.3.0) for desktop tests.
-- Run with a Lua 5.4 built with LUA_32BITS=1 so numbers match the device.
--
--   local E = dofile("test/e16mock.lua")
--   E.load("lfo.lua")          -- run the script and page.onInit()
--   E.turn(1, 1); E.press(17)  -- ids follow the scene convention:
--                              -- page 1 turns 1-16 / pushes 17-32,
--                              -- page 2 turns 33-48 / pushes 49-64
--   E.run(1000)                -- advance time, calling system.update() and the clock
--   E.release(17, 300)         -- let go of a push after 300 ms
--   E.extStart(128); E.extStop(); E.extContinue()   -- external MIDI transport
--   E.check(ok, "message"); E.done()

local M = {now = 0, rate = 0, sent = {}, rings = {}, labels = {}, title = "",
  store = {}, page = 1, fails = 0, lastU = 0,
  -- clock: internal and external tempo, running source (nil = stopped),
  -- MIDI tick count (24 per quarter), time of the next tick, queued callbacks
  bpm = 120, extBpm = 120, tp = nil, tick = 0, nextPulse = 0, q = {},
  at = 0, atTick = 0,         -- time and tick the pulse grid is anchored at
  listening = false, res = 16, hold = 0,
  cerrs = 0}                  -- clock callback errors (logged; listening continues)

function M.check(ok, msg)
  if ok then print("ok   " .. msg) else M.fails = M.fails + 1; print("FAIL: " .. msg) end
end

local function byte(v, what)
  assert(math.type(v) == "integer" and v >= 0 and v <= 127, what .. " out of range: " .. tostring(v))
end

midi = {
  sendMidi = function(o, c, s, a, b)
    assert(math.type(s) == "integer" and s >= 0x80 and s <= 0xFF, "bad status " .. tostring(s))
    byte(a, "data1"); byte(b, "data2")
    M.sent[#M.sent + 1] = {t = M.now, out = o, st = s, d1 = a, d2 = b}
  end,
  sendCC = function(o, c, cc, v)
    assert(c >= 0 and c <= 15, "channel out of range: " .. tostring(c))
    byte(cc, "cc"); byte(v, "cc value")
    M.sent[#M.sent + 1] = {t = M.now, out = o, st = 0xB0 + c, d1 = cc, d2 = v}
  end,
  sendPC = function() end,
  sendSysex = function() end,
  listen = function() end,
}
leds = {
  updateByIndex = function(i, v, c)
    if type(i) == "table" then                  -- batch form: {{index, value, color}, ...}
      for _, e in ipairs(i) do leds.updateByIndex(e[1], e[2], e[3] or 0) end
      return
    end
    c = c or 0
    assert(i >= 1 and i <= 16, "led index " .. tostring(i))
    assert(v >= 0 and v <= 16383, "led value " .. tostring(v))
    assert(c >= 0 and c <= 100, "led color " .. tostring(c))
    M.rings[i] = {v = v, c = c}
  end,
  update = function() end,
  reset = function(i) M.rings[i] = nil end,
  resetById = function() end,
}
slots = {
  update = function(i, s)
    assert(i >= 1 and i <= 16, "slot index")
    assert(type(s) == "string", "label must be a string")
    assert(#s <= 4, "label too long: '" .. s .. "'")
    M.labels[i] = s
  end,
  reset = function(i) M.labels[i] = nil end,
}
page = {
  setTitle = function(s) assert(#s <= 15, "title too long: '" .. s .. "'"); M.title = s end,
  resetTitle = function() end,
}
controller = {
  getPage = function() return M.page end,
  set = function() end, setByIndex = function() end, setControls = function() end,
  get = function() end,
  setHoldTime = function(ms) M.hold = ms == 0 and 0 or math.max(30, math.min(3000, ms)) end,
}
var = {
  register = function(n, ty, d)
    assert(#n <= 16, "var name too long: " .. n)
    if M.store[n] == nil then
      local count = 0
      for _ in pairs(M.store) do count = count + 1 end
      assert(count < 32, "more than 32 vars registered (" .. n .. ")")
      M.store[n] = d
    end
  end,
  get = function(n) return M.store[n] end,
  set = function(n, v) if M.store[n] ~= nil then M.store[n] = v end end,
  delete = function(n) M.store[n] = nil end,
  deleteAll = function() M.store = {} end,
}
system = {
  setUpdateRate = function(ms)
    M.rate = (ms >= 5 and ms <= 1000) and ms // 1 or 0
    M.lastU = M.now
  end,
}

-- Store: store.data survives reloads (a scene exit saves it). size() estimates
-- the saved size like the guide describes; the device keeps at most 1024 bytes.
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[copy(k)] = copy(x) end
  return t
end
local function ssize(v)
  local t = type(v)
  if t == "boolean" then return 1 end
  if t == "string" then return #v + 2 end
  if t == "number" then
    assert(math.type(v) == "integer", "store: only integers here (" .. tostring(v) .. ")")
    return (v >= 0 and v < 128) and 1 or v < 16384 and v > -16384 and 2 or 5
  end
  assert(t == "table", "store can't hold a " .. t)
  local n = 2
  for k, x in pairs(v) do n = n + ssize(k) + ssize(x) end
  return n
end
store = {
  use = function() end,
  size = function() return ssize(store.data) end,
  capacity = function() return 1024 end,
}

-- Clock: transport callbacks are queued and delivered on the next clock pass
-- (the next M.run), before that pass's first pulse, as the guide describes.
local function cb(name, ...) M.q[#M.q + 1] = {name, ...} end
-- A clock callback error ends that call only, as on the device (it's logged).
local function safe(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then
    if M.cerrs == 0 then print("clock callback error: " .. tostring(err)) end
    M.cerrs = M.cerrs + 1
  end
end
local function flush()
  local q = M.q
  if #q == 0 then return end                     -- (no garbage per pass)
  M.q = {}
  for _, e in ipairs(q) do
    if M.listening and clock[e[1]] then safe(clock[e[1]], table.unpack(e, 2)) end
  end
end
local RES = {[4] = true, [8] = true, [16] = true, [32] = true, [96] = true}
clock = {
  listen = function(on, res)
    assert(type(on) == "boolean", "clock.listen needs a boolean")
    M.listening, M.res = on, RES[res] and res or 16
  end,
  startInternal = function()
    if M.tp and M.tp > 0 then return end        -- already running: unchanged
    if M.tp == 0 then cb("onStop", 0) end        -- takes over from external transport
    M.tp, M.tick, M.nextPulse, M.at, M.atTick = 2, 0, M.now, M.now, 0
    cb("onStart", 2)
  end,
  stopInternal = function()
    if M.tp and M.tp > 0 then M.tp = nil; cb("onStop", 2) end
  end,
  setInternalBpm = function(b)
    assert(type(b) == "number", "setInternalBpm needs a number")
    if b >= 20 and b <= 300 then
      if M.tp and M.tp > 0 then M.at, M.atTick = M.nextPulse, M.tick end   -- re-anchor the grid
      M.bpm = b
    end
  end,
  getBpm = function() return M.tp == 0 and M.extBpm or M.tp and M.bpm or 1 end,
  getPosition = function(res)
    return M.tp and M.tick // (96 // (RES[res] and res or 16)) or 0
  end,
}
-- External transport. Start and Continue don't replace a running internal clock;
-- Stop stops any clock (and repeats reach the script even when stopped).
function M.extStart(bpm)
  M.extBpm = bpm or M.extBpm
  if M.tp and M.tp > 0 then return end
  M.tp, M.tick, M.nextPulse, M.at, M.atTick = 0, 0, M.now, M.now, 0
  cb("onStart", 0)
end
function M.extContinue()
  if M.tp then return end
  M.tp, M.nextPulse, M.at, M.atTick = 0, M.now, M.now, M.tick
  cb("onContinue", 0)
end
function M.extStop()
  M.tp = nil
  cb("onStop", 0)
end

local function pulse()
  local every = 96 // M.res
  if M.listening and M.tick % every == 0 then
    local t = M.tick
    local b = t % 24 == 0 and 4 or t % 12 == 0 and 8 or t % 6 == 0 and 16 or t % 3 == 0 and 32 or 96
    if clock.onPulse then safe(clock.onPulse, b, t // every, M.tp) end
  end
  M.tick = M.tick + 1
  -- from the anchor, so float32 time doesn't drift
  M.nextPulse = M.at + (M.tick - M.atTick) * 60000 / ((M.tp == 0 and M.extBpm or M.bpm) * 24)
end

-- Load (or reload, like a scene re-entry) a script. Vars survive in M.store.
-- Loading turns clock listening off and stops an internal clock Lua started.
function M.load(path)
  if store.data then                              -- leaving the scene saves the store
    assert(ssize(store.data) <= 1024, "store over 1024 bytes: " .. ssize(store.data))
    M.saved = copy(store.data)
  end
  store.data = copy(M.saved or {})
  M.sent, M.rings, M.labels, M.page = {}, {}, {}, 1
  M.listening, M.hold, M.q = false, 0, {}
  if M.tp == 2 then M.tp = nil end
  M.lastU = M.now
  dofile(path)
  page.onInit()
end

-- Advance time by ms, calling system.update() the way the firmware does
-- (once more than `rate` ms have passed: rate + 0.1 ms on a 10 kHz tick),
-- and the clock callbacks (24 ticks per quarter note while transport runs).
function M.run(ms)
  local stop = M.now + ms
  while true do
    flush()
    local tu = M.rate > 0 and M.lastU + M.rate + 0.1 or math.huge
    local tc = M.tp and M.nextPulse or math.huge
    local t = math.min(tu, tc)
    if t > stop then break end
    M.now = math.max(M.now, t)
    if tc <= tu then
      pulse()
    else
      M.lastU = t
      local ok, err = pcall(system.update)
      if not ok then M.rate = 0; error("update() raised (firmware would disable updates): " .. err) end
    end
  end
  if M.now < stop then M.now = stop end
end

local function where(id, base)
  local pg = id > base + 16 and 2 or 1
  return (id - base - 1) % 16 + 1, pg
end

function M.turn(id, inc)
  local index, pg = where(id > 32 and id - 16 or id, 0)
  controller.onEncoderTurn{id = id, index = index, page = pg, increment = inc,
    value = 8192, scaled = 64, is_held = false}
end

-- A push fires on touchdown; release follows (held_ms), and hold after the
-- time armed with controller.setHoldTime if the push lasts that long.
function M.press(id)
  local index, pg = where(id > 48 and id - 32 or id - 16, 0)
  controller.onEncoderPress{id = id, index = index, page = pg, value = 8192, scaled = 64}
end

function M.release(id, held)
  local index, pg = where(id > 48 and id - 32 or id - 16, 0)
  held = held or 100
  if M.hold > 0 and held >= M.hold and controller.onEncoderHold then
    controller.onEncoderHold{id = id, index = index, page = pg, value = 8192, scaled = 64}
  end
  if controller.onEncoderRelease then
    controller.onEncoderRelease{id = id, index = index, page = pg, value = 8192, scaled = 64, held_ms = held}
  end
end

function M.show(pg)
  local prev = M.page
  M.page = pg
  page.onPageChange(prev, pg)
end

-- Messages sent so far, filtered: M.msgs(0xB0, 74) = CCs 74 on channel 1
function M.msgs(status, d1)
  local r = {}
  for _, m in ipairs(M.sent) do
    if (not status or m.st == status) and (not d1 or m.d1 == d1) then r[#r + 1] = m end
  end
  return r
end

function M.done()
  print(M.fails == 0 and "\nALL PASSED" or ("\n" .. M.fails .. " FAILED"))
  os.exit(M.fails == 0 and 0 or 1)
end

return M
