-- Appended to a script by tools/make_diag.py: catch errors in every callback and
-- show them on the device (no Lua Debug view on firmware 1.2). The header shows
-- "ERR <callback>", and the 16 labels show the message, 4 characters each.
do
  local shown = false
  local function show(where, e)
    if shown then return end
    shown = true
    e = (tostring(e):gsub("^.-:%d+: ", ""))
    page.setTitle(("ERR " .. where):sub(1, 15))
    for i = 1, 16 do slots.update(i, e:sub(i * 4 - 3, i * 4)) end
  end
  local function wrap(t, k, where)
    local f = t[k]
    if f then
      t[k] = function(...)
        local ok, e = pcall(f, ...)
        if not ok then show(where, e) end
      end
    end
  end
  wrap(page, "onInit", "init")
  wrap(page, "onPageChange", "page")
  wrap(page, "onVarChange", "var")
  wrap(controller, "onEncoderTurn", "turn")
  wrap(controller, "onEncoderPress", "press")
  wrap(controller, "onSysex", "sysex")
  wrap(system, "update", "update")
end
