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
      local id = (pg == pages and pages > 1) and 48 + e or 16 + e
      controller.onEncoderPress{id = id, index = e, page = pg, value = 8192, scaled = 64}
      if controller.onEncoderRelease and math.random(4) > 1 then      -- usually let go soon
        E.run(math.random(0, 200))
        controller.onEncoderRelease{id = id, index = e, page = pg, value = 8192, scaled = 64,
          held_ms = math.random(0, 3000)}
      end
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
    elseif r <= 92 then                 -- external transport, and internal tempo changes
      local x = math.random(4)
      if x == 1 then E.extStart(math.random(20, 300))
      elseif x == 2 then E.extStop()
      elseif x == 3 then E.extContinue()
      else clock.setInternalBpm(math.random(20, 300)) end
    end
    local dt = math.random(0, 300)
    E.run(dt)
    t = t + dt
    -- scripts that catch their own errors show "ERR" (maybe with the message) in the header instead of raising
    if E.title:sub(1, 3) == "ERR" then
      error("script reported an error: " .. E.title .. " " .. table.concat(E.labels, "", 9, 16))
    end
  end
end)
ok = ok and E.cerrs == 0 or false
print(("%-12s %s"):format(script, ok and ("ok, " .. #E.sent .. " messages, update still running: " .. tostring(E.rate > 0))
  or ("ERROR: " .. tostring(err or (E.cerrs .. " clock callback errors")))))
os.exit(ok and E.rate > 0 and 0 or 1)
