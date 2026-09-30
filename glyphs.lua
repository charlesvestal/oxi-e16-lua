-- PROBE: what can the E16 screen show? (groundwork for an ASCII game view)
--
-- Push encoder 16 for the next screen, encoder 1 for the previous one.
-- The title names the screen; photograph each one.
--   Layout      each label is its slot number: where the 16 slots sit
--   Chr a-b     each label shows 4 consecutive character codes, so slot i
--               starts at code a + 4*(i-1) (32-95, 96-159)
--   Icon a-b    one code per slot: its number, then its glyph (128-143, 144-159)
--   Mono        fixed-width and space test: rows should line up column by column
--   Width       each row starts with "####"; the other slots are "#xx#" for a
--               candidate x (space, 146, 154, 156, = + : / \ _ o and 135). A
--               slot as wide as "####" means x is as wide as "#".
--   Anim Nms    "####" and a white ring step one slot per tick. Turn encoder 1
--               to change the tick. Watch for flicker, tearing or lag.

--@assign id=1 abbr="E1"
--@assign id=2 abbr="E2"
--@assign id=3 abbr="E3"
--@assign id=4 abbr="E4"
--@assign id=5 abbr="E5"
--@assign id=6 abbr="E6"
--@assign id=7 abbr="E7"
--@assign id=8 abbr="E8"
--@assign id=9 abbr="E9"
--@assign id=10 abbr="E10"
--@assign id=11 abbr="E11"
--@assign id=12 abbr="E12"
--@assign id=13 abbr="E13"
--@assign id=14 abbr="E14"
--@assign id=15 abbr="E15"
--@assign id=16 abbr="E16"
--@assign id=17 abbr="Prev" name="Previous screen" p=true
--@assign id=32 abbr="Next" name="Next screen" p=true
-- pages: Glyphs

local N = 8                         -- screens: layout, 2 x chars, 2 x icons, mono, width, anim
local RATE = {20, 30, 50, 80, 120, 200}
local MONO = {"####", "####", "####", "####",
              "iiii", "MMMM", "#  #", " ## ",
              "|/\\-", "____", "#   ", "   #",
              "#.#.", ".#.#", "  ##", "##  "}
local WID = {32, 146, 154, 156, 61, 43, 58, 47, 92, 95, 111, 135}
local m, r, tick = 1, 3, 0
local title                         -- pending header text
local on = true                     -- our page is shown

local function show()
  if not on then return end
  local t
  for i = 1, 16 do leds.reset(i) end
  if m == 1 then
    t = "Layout"
    for i = 1, 16 do slots.update(i, "" .. i) end
  elseif m <= 3 then
    local c0 = 32 + 64 * (m - 2)
    t = "Chr " .. c0 .. "-" .. c0 + 63
    for i = 1, 16 do
      local a = c0 + 4 * (i - 1)
      slots.update(i, string.char(a, a + 1, a + 2, a + 3))
    end
  elseif m <= 5 then
    local c0 = 128 + 16 * (m - 4)
    t = "Icon " .. c0 .. "-" .. c0 + 15
    for i = 1, 16 do slots.update(i, c0 + i - 1 .. string.char(c0 + i - 1)) end
  elseif m == 6 then
    t = "Mono"
    for i = 1, 16 do slots.update(i, MONO[i]) end
  elseif m == 7 then
    t = "Width"
    for i = 1, 16 do
      local x = i % 4 == 1 and "#" or string.char(WID[i - (i + 3) // 4])
      slots.update(i, "#" .. x .. x .. "#")
    end
  else
    t = "Anim " .. RATE[r] .. "ms"
    for i = 1, 16 do slots.update(i, "") end
  end
  system.setUpdateRate(m == N and RATE[r] or 50)
  page.resetTitle()                 -- title freeze workaround: set on next tick
  title = t
end

function system.update()
  if title then page.setTitle(title); title = nil end
  if m ~= N or not on then return end
  local q = tick % 16 + 1
  tick = tick + 1
  local p = tick % 16 + 1
  slots.update(q, "")
  leds.updateByIndex(q, 0, 0)
  slots.update(p, "####")
  leds.updateByIndex(p, 16383, 34)
end

function controller.onEncoderTurn(e)
  if e.id == 1 and m == N and e.increment ~= 0 then
    r = math.max(1, math.min(#RATE, r + (e.increment > 0 and 1 or -1)))
    show()
  end
end

function controller.onEncoderPress(e)
  if e.id == 17 then m = (m - 2) % N + 1 show()
  elseif e.id == 32 then m = m % N + 1 show() end
end

function page.onPageChange(prev, curr)
  on = curr == 1
  if on then show() else
    for i = 1, 16 do slots.reset(i); leds.reset(i) end
    page.resetTitle()
  end
end

function page.onInit()
  show()
end
