-- Tiny settings manager.
--   Defaults live in lua/config/settings.lua (edit by hand).
--   Changes made with :Settings are saved to stdpath("data")/user-settings.json
--   and override the defaults on every startup.
local M = {}

M.file = vim.fn.stdpath("data") .. "/user-settings.json"

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Settings" })
end

local function read()
  local f = io.open(M.file, "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  return (ok and type(data) == "table") and data or {}
end

local function write()
  local f, err = io.open(M.file, "w")
  if not f then
    return notify("Could not write " .. M.file .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  f:write(vim.json.encode(M.overrides))
  f:close()
end

M.overrides = read()

function M.defaults()
  local ok, d = pcall(require, "config.settings")
  return ok and d or {}
end

--- Defaults merged with saved overrides
function M.get()
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults()), M.overrides)
end

local function apply(section, key, value)
  if section == "options" then
    local ok, err = pcall(function()
      vim.opt[key] = value
    end)
    if not ok then
      notify("Invalid option " .. key .. ": " .. tostring(err), vim.log.levels.WARN)
    end
  elseif section == "globals" then
    vim.g[key] = value
  elseif section == "colorscheme" then
    local ok = pcall(vim.cmd.colorscheme, value)
    if not ok then
      notify("Colorscheme not found: " .. tostring(value), vim.log.levels.WARN)
    end
  end
end

function M.set(section, key, value)
  if section == "colorscheme" then
    M.overrides.colorscheme = value
  else
    M.overrides[section] = M.overrides[section] or {}
    M.overrides[section][key] = value
  end
  write()
  apply(section, key, value)
end

--- Reset one key, or everything when key is nil
function M.reset(key)
  if not key then
    M.overrides = {}
  else
    if key == "colorscheme" then
      M.overrides.colorscheme = nil
    end
    for _, s in ipairs({ "options", "globals" }) do
      if M.overrides[s] then
        M.overrides[s][key] = nil
      end
    end
  end
  write()
  local d = M.defaults()
  for _, s in ipairs({ "options", "globals" }) do
    for k, v in pairs(d[s] or {}) do
      if not key or k == key then
        apply(s, k, v)
      end
    end
  end
  notify("Reset " .. (key or "all settings") .. ". Restart Neovim for everything to take effect.")
end

local function is_custom(item)
  if item.section == "colorscheme" then
    return M.overrides.colorscheme ~= nil
  end
  return M.overrides[item.section] ~= nil and M.overrides[item.section][item.key] ~= nil
end

function M.edit(item, done)
  done = done or function() end
  local section, key, value = item.section, item.key, item.value

  if type(value) == "boolean" then
    M.set(section, key, not value)
    return done()
  end

  if section == "colorscheme" then
    return vim.ui.select(vim.fn.getcompletion("", "color"), { prompt = "Colorscheme" }, function(choice)
      if choice then
        M.set("colorscheme", nil, choice)
      end
      done()
    end)
  end

  vim.ui.input({ prompt = key .. ": ", default = tostring(value) }, function(input)
    if input then
      local new = type(value) == "number" and tonumber(input) or input
      if new == nil then
        notify(key .. " expects a number", vim.log.levels.WARN)
      else
        M.set(section, key, new)
      end
    end
    done()
  end)
end

function M.add(done)
  vim.ui.input({ prompt = "Option name (e.g. cursorline): ", completion = "option" }, function(name)
    if not name or name == "" then
      return
    end
    local ok, info = pcall(vim.api.nvim_get_option_info2, name, {})
    if not ok then
      return notify("Unknown option: " .. name, vim.log.levels.WARN)
    end
    M.edit({ section = "options", key = info.name, value = vim.o[info.name] }, done)
  end)
end

function M.open()
  local s = M.get()
  local items = {}
  for _, section in ipairs({ "options", "globals" }) do
    for k, v in pairs(s[section] or {}) do
      if type(v) ~= "table" and type(v) ~= "function" then
        -- show the live value so toggles reflect reality
        local current = section == "options" and vim.o[k] or vim.g[k]
        if current == nil then
          current = v
        end
        items[#items + 1] = { section = section, key = k, value = current }
      end
    end
  end
  table.sort(items, function(a, b)
    return a.key < b.key
  end)
  if s.colorscheme then
    items[#items + 1] = { section = "colorscheme", key = "colorscheme", value = s.colorscheme }
  end
  items[#items + 1] = { section = "add", key = "+ Add option…" }

  vim.ui.select(items, {
    prompt = "Settings",
    format_item = function(i)
      if i.section == "add" then
        return i.key
      end
      return string.format("%-12s %-22s %s%s", i.section, i.key, vim.inspect(i.value), is_custom(i) and "  ●" or "")
    end,
  }, function(item)
    if not item then
      return
    end
    local reopen = vim.schedule_wrap(M.open)
    if item.section == "add" then
      M.add(reopen)
    else
      M.edit(item, reopen)
    end
  end)
end

--- Lazy specs built from the `plugins` table and colorscheme
function M.specs()
  local s = M.get()
  local specs = {}
  for name, spec in pairs(s.plugins or {}) do
    if type(spec) == "boolean" then
      spec = { enabled = spec }
    end
    specs[#specs + 1] = vim.tbl_extend("force", { name }, spec)
  end
  if s.colorscheme then
    specs[#specs + 1] = { "LazyVim/LazyVim", opts = { colorscheme = s.colorscheme } }
  end
  return specs
end

function M.setup()
  local s = M.get()
  for k, v in pairs(s.options or {}) do
    apply("options", k, v)
  end
  for k, v in pairs(s.globals or {}) do
    apply("globals", k, v)
  end

  vim.api.nvim_create_user_command("Settings", function(o)
    if o.fargs[1] == "reset" then
      M.reset(o.fargs[2])
    else
      M.open()
    end
  end, {
    nargs = "*",
    desc = "Edit Neovim settings",
    complete = function()
      return { "reset" }
    end,
  })
end

return M
