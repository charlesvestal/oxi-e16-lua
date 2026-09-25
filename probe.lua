-- PROBE: measure the E16's Lua heap ceiling.
--
-- Allocates 256 bytes more every update (~20 ms) and keeps it. Shows Lua's heap
-- count (tenths of a KB) on encoder 1 and in the header ("Heap 31.5KB"), a tick
-- counter on encoder 2, and saves the count in the scene variable "peak"
-- (tenths of a KB). When memory runs out, the allocation raises an error, the
-- firmware stops calling update, and everything freezes on the last value:
-- that is the ceiling (Lua's own count, excluding allocator overhead).
--
-- No float formatting: the device's printf may not support %f.
-- Push encoder 1 (page 1) to restart.

--@assign id=17 abbr="Heap" name="Restart probe" p=true g=1
-- pages: Prb,-

local keep, n = {}, 0

local function kb10() return math.floor(collectgarbage("count") * 10) end

function system.update()
  n = n + 1
  keep[n] = string.rep(n .. "-", 64)              -- ~256+ bytes, unique per step
  local k = kb10()
  var.set("peak", k)
  slots.update(1, "" .. k // 10)
  slots.update(2, "" .. n % 10000)
  if n % 10 == 0 then page.resetTitle()            -- title freeze workaround:
  elseif n % 10 == 1 then                          -- reset, then set next tick
    page.setTitle("Heap " .. k // 10 .. "." .. k % 10 .. "KB")
  end
end

function controller.onEncoderPress(e)
  if e.id == 17 then
    keep, n = {}, 0
    collectgarbage()
    system.setUpdateRate(20)
  end
end

function page.onInit()
  var.register("peak", "int", 0)
  collectgarbage()
  page.setTitle("Heap probe")
  system.setUpdateRate(20)
end
