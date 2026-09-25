-- Mock of the OXI E16 Lua API (firmware 1.2.0) for desktop tests.
-- Run with a Lua 5.4 built with LUA_32BITS=1 so numbers match the device.
--
--   local E = dofile("test/e16mock.lua")
--   E.load("lfo.lua")          -- run the script and page.onInit()
--   E.turn(1, 1); E.press(17)  -- ids follow the scene convention:
--                              -- page 1 turns 1-16 / pushes 17-32,
--                              -- page 2 turns 33-48 / pushes 49-64
--   E.run(1000)                -- advance time, calling system.update()
--   E.check(ok, "message"); E.done()

local M = {now = 0, rate = 0, sent = {}, rings = {}, labels = {}, title = "",
  store = {}, page = 1, fails = 0}

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
  setUpdateRate = function(ms) M.rate = (ms >= 20 and ms <= 1000) and ms // 1 or 0 end,
}

-- Load (or reload, like a scene re-entry) a script. Vars survive in M.store.
function M.load(path)
  M.sent, M.rings, M.labels, M.page = {}, {}, {}, 1
  dofile(path)
  page.onInit()
end

-- Advance time by ms, calling system.update() the way the firmware does
-- (once more than `rate` ms have passed: rate + 0.1 ms on a 10 kHz tick).
function M.run(ms)
  local stop = M.now + ms
  while M.rate > 0 and M.now + M.rate + 0.1 <= stop do
    M.now = M.now + M.rate + 0.1
    local ok, err = pcall(system.update)
    if not ok then M.rate = 0; error("update() raised (firmware would disable updates): " .. err) end
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

function M.press(id)
  local index, pg = where(id > 48 and id - 32 or id - 16, 0)
  controller.onEncoderPress{id = id, index = index, page = pg, value = 8192, scaled = 64}
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
