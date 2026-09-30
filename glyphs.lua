-- PROBE: what can the E16 screen show? (groundwork for an ASCII game view)
--
-- Push encoder 16 for the next screen, encoder 1 for the previous one.
-- The title names the screen; photograph each one.
--   Layout      each label is its slot number: where the 16 slots sit
--   Chr a-b     each label shows 4 consecutive character codes, so slot i
--               starts at code a + 4*(i-1) (4 screens: 32-95 ... 224-255)
--   Disp        label dN: encoder N+1's turn uses display mode N (set in the
--               scene). Its value line shows that format; turn it to see more.
--   Anim Nms    "####" and a white ring step one slot per tick. Turn encoder 1
--               to change the tick. Watch for flicker, tearing or lag.
-- Every value starts at mid-scale (8192).

--@assign id=1 abbr="E1" dis=0
--@assign id=2 abbr="E2" dis=1
--@assign id=3 abbr="E3" dis=2
--@assign id=4 abbr="E4" dis=3
--@assign id=5 abbr="E5" dis=4
--@assign id=6 abbr="E6" dis=5
--@assign id=7 abbr="E7" dis=6
--@assign id=8 abbr="E8" dis=7
--@assign id=9 abbr="E9" dis=8
--@assign id=10 abbr="E10" dis=9
--@assign id=11 abbr="E11" dis=10
--@assign id=12 abbr="E12" dis=11
--@assign id=13 abbr="E13" dis=12
--@assign id=14 abbr="E14" dis=13
--@assign id=15 abbr="E15" dis=14
--@assign id=16 abbr="E16" dis=15
--@assign id=17 abbr="Prev" name="Previous screen" p=true
--@assign id=32 abbr="Next" name="Next screen" p=true
-- pages: Glyphs

local N = 7                         -- screens: layout, 4 x chars, disp, anim
local RATE = {20, 30, 50, 80, 120, 200}
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
  elseif m <= 5 then
    local c0 = 32 + 64 * (m - 2)
    t = "Chr " .. c0 .. "-" .. math.min(c0 + 63, 255)
    for i = 1, 16 do
      local a, s = c0 + 4 * (i - 1), ""
      for c = a, math.min(a + 3, 255) do s = s .. string.char(c) end
      slots.update(i, s)
    end
  elseif m == 6 then
    t = "Disp"
    for i = 1, 16 do slots.update(i, "d" .. i - 1) end
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
  for i = 1, 16 do controller.set(i, "v", 8192) end
  show()
end
