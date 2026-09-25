-- Fuzz a script with random events; update() must never raise (on the E16 an
-- error there silently stops all updates), and no script may report "ERR". Run from the repo root:
--   lua test/fuzz.lua SCRIPT.lua [pages] [seconds]
local E = dofile("test/e16mock.lua")
local script, pages, secs = arg[1], tonumber(arg[2] or 2), tonumber(arg[3] or 600)
math.randomseed(1)
local ok, err = pcall(function()
  E.load(script)
  local t = 0
  while t < secs * 1000 do
    local r = math.random(100)
    if r <= 35 then
      local pg = math.random(pages)
      E.page = pg
      local e = math.random(16)
      controller.onEncoderPress{id = (pg == pages and pages > 1) and 48 + e or 16 + e, index = e, page = pg,
        value = 8192, scaled = 64}
    elseif r <= 80 then
      local pg = math.random(pages)
      E.page = pg
      local e = math.random(16)
      local inc = ({-8, -4, -2, -1, 1, 2, 4, 8})[math.random(8)]
      controller.onEncoderTurn{id = (pg == pages and pages > 1) and 32 + e or e, index = e, page = pg,
        increment = inc, value = 8192, scaled = math.random(0, 127), is_held = false}
    elseif r <= 85 then
      E.show(math.random(12))
    elseif r <= 88 then
      local k = next(E.store)
      local n = 0
      for name in pairs(E.store) do n = n + 1; if math.random(n) == 1 then k = name end end
      if k then E.store[k] = math.random(-50, 400); page.onVarChange(k) end
    end
    local dt = math.random(0, 300)
    E.run(dt)
    t = t + dt
    -- scripts that catch their own errors show "ERR" in the header instead of raising
    if E.title == "ERR" then error("script reported an error: " .. table.concat(E.labels, "", 9, 16)) end
  end
end)
print(("%-12s %s"):format(script, ok and ("ok, " .. #E.sent .. " messages, update still running: " .. tostring(E.rate > 0)) or ("ERROR: " .. err)))
os.exit(ok and E.rate > 0 and 0 or 1)
