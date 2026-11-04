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
-- ── Info ──────────────────────────────────────────────────────────────

local help_tags -- cache: help tag -> absolute help file path

local function find_help_file(tag)
  if not help_tags then
    help_tags = {}
    for _, tagfile in ipairs(vim.api.nvim_get_runtime_file("doc/tags", true)) do
      local dir = vim.fn.fnamemodify(tagfile, ":h")
      for line in io.lines(tagfile) do
        local t, file = line:match("^([^\t]+)\t([^\t]+)")
        if t and not help_tags[t] then
          help_tags[t] = dir .. "/" .. file
        end
      end
    end
  end
  return help_tags[tag]
end

--- Lines from Neovim's :help for an option
local function help_excerpt(name)
  local tag = "'" .. name .. "'"
  local file = find_help_file(tag)
  if not file then
    return nil
  end
  local lines = vim.fn.readfile(file)
  local needle = "*" .. tag .. "*"
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      local out = {}
      for j = i + 1, math.min(i + 40, #lines) do
        local line = lines[j]
        -- stop at the next option's tag line
        if j > i + 1 and line:match("^%s*%*'[^']+'%*") then
          break
        end
        out[#out + 1] = line
      end
      while #out > 0 and out[#out]:match("^%s*$") do
        table.remove(out)
      end
      return out
    end
  end
end

local function float(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = math.min(90, vim.o.columns - 4)
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true })
  end
end

local function collect_items()
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
  return items
end

--- Build the info text for one setting
function M.describe(name)
  local descs = M.get().descriptions or {}
  local defaults = M.defaults()
  local fmt = function(v)
    return v == nil and "–" or vim.inspect(v)
  end

  local ok, info = pcall(vim.api.nvim_get_option_info2, name, {})
  if ok then
    name = info.name -- resolve short names, e.g. "nu" -> "number"
  end

  local lines = { "# " .. name, "" }
  if descs[name] then
    vim.list_extend(lines, vim.split(descs[name], "\n"))
    lines[#lines + 1] = ""
  end

  if name == "colorscheme" then
    vim.list_extend(lines, {
      "- **Kind:** colorscheme (applied through LazyVim)",
      "- **Current:** " .. fmt(vim.g.colors_name),
      "- **Your default:** " .. fmt(defaults.colorscheme),
      "- **Saved from menu:** " .. fmt(M.overrides.colorscheme),
    })
  elseif ok then
    local short = info.shortname ~= "" and (", short name `" .. info.shortname .. "`") or ""
    vim.list_extend(lines, {
      "- **Kind:** Neovim option (`vim.opt." .. name .. "`)" .. short,
      "- **Type:** " .. info.type .. ", **scope:** " .. info.scope,
      "- **Neovim default:** " .. fmt(info.default),
      "- **Current:** " .. fmt(vim.o[name]),
      "- **Your default:** " .. fmt((defaults.options or {})[name]),
      "- **Saved from menu:** " .. fmt((M.overrides.options or {})[name]),
    })
    local help = help_excerpt(name)
    if help then
      vim.list_extend(lines, { "", "## From `:help '" .. name .. "'`", "", "```vimdoc" })
      vim.list_extend(lines, help)
      lines[#lines + 1] = "```"
    end
  else
    vim.list_extend(lines, {
      "- **Kind:** global variable (`vim.g." .. name .. "`)",
      "- **Current:** " .. fmt(vim.g[name]),
      "- **Your default:** " .. fmt((defaults.globals or {})[name]),
      "- **Saved from menu:** " .. fmt((M.overrides.globals or {})[name]),
    })
    if not descs[name] then
      vim.list_extend(lines, { "", "_No description yet. Add one under `descriptions` in lua/config/settings.lua._" })
    end
  end

  vim.list_extend(lines, { "", "_q / Esc to close_" })
  return lines
end

--- Show info for a setting, or pick one first
function M.info(name)
  if name and name ~= "" then
    return float(M.describe(name), name)
  end
  local descs = M.get().descriptions or {}
  vim.ui.select(collect_items(), {
    prompt = "Info about…",
    format_item = function(i)
      return string.format("%-22s %s", i.key, descs[i.key] or "")
    end,
  }, function(item)
    if item then
      M.info(item.key)
    end
  end)
end
function M.open()
  local items = collect_items()
  local descs = M.get().descriptions or {}
  items[#items + 1] = { section = "add", key = "+ Add option…" }
  items[#items + 1] = { section = "info", key = "ⓘ Info about a setting…" }

  vim.ui.select(items, {
    prompt = "Settings",
    format_item = function(i)
      if i.section == "add" or i.section == "info" then
        return i.key
      end
      local line =
        string.format("%-12s %-22s %-12s%s", i.section, i.key, vim.inspect(i.value), is_custom(i) and " ●" or "  ")
      if descs[i.key] then
        line = line .. "  " .. descs[i.key]
      end
      return line
    end,
  }, function(item)
    if not item then
      return
    end
    local reopen = vim.schedule_wrap(M.open)
    if item.section == "add" then
      M.add(reopen)
    elseif item.section == "info" then
      M.info()
    else
      M.edit(item, reopen)
    end
  end)
end --- Lazy specs built from the `plugins` table and colorscheme
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

vim.api.nvim_create_user_command("Settings", function(o)
  local sub, arg = o.fargs[1], o.fargs[2]
  if sub == "reset" then
    M.reset(arg)
  elseif sub == "info" then
    M.info(arg)
  else
    M.open()
  end
end, {
  nargs = "*",
  desc = "Edit Neovim settings",
  complete = function(arglead, cmdline)
    -- after "info " or "reset ", complete setting names
    if cmdline:match("^%S+%s+%S+%s+") then
      local names = vim.tbl_map(function(i)
        return i.key
      end, collect_items())
      return vim.tbl_filter(function(n)
        return vim.startswith(n, arglead)
      end, names)
    end
    return { "info", "reset" }
  end,
})
return M
