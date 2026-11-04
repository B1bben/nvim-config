local M = {}

local path = vim.fn.stdpath("config") .. "/keymaps.json"
local modes = { "n", "x", "i", "o", "t" }

-- storage --------------------------------------------------------------

local function read()
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return (ok and type(data) == "table") and data or {}
end

local function write(data)
  local f = io.open(path, "w")
  if not f then
    return vim.notify("keymap-editor: cannot write " .. path, vim.log.levels.ERROR)
  end
  f:write(vim.json.encode(data))
  f:close()
end

-- applying changes -----------------------------------------------------

local function get(mode, lhs)
  local m = vim.fn.maparg(lhs, mode, false, true)
  if vim.tbl_isempty(m) or m.buffer == 1 then
    return nil
  end
  return m
end

local function copy(mode, lhs, m, desc)
  vim.keymap.set(mode, lhs, m.callback or m.rhs, {
    desc = desc or m.desc,
    silent = m.silent == 1,
    expr = m.expr == 1,
    nowait = m.nowait == 1,
    remap = m.noremap == 0,
  })
end

local function apply_one(o)
  if o.action == "add" then
    vim.keymap.set(o.mode, o.lhs, o.rhs, { desc = o.desc })
  elseif o.action == "disable" then
    if get(o.mode, o.lhs) then
      pcall(vim.keymap.del, o.mode, o.lhs)
    end
  elseif o.action == "desc" then
    local m = get(o.mode, o.lhs)
    if m then
      copy(o.mode, o.lhs, m, o.desc)
    end
  elseif o.action == "rebind" then
    local m = get(o.mode, o.from)
    if m then
      pcall(vim.keymap.del, o.mode, o.from)
      copy(o.mode, o.to, m)
    end
  end
end

function M.apply()
  for _, o in ipairs(read()) do
    pcall(apply_one, o)
  end
end

local function save(o)
  local data = read()
  table.insert(data, o)
  write(data)
  apply_one(o)
  vim.notify("keymap-editor: saved")
end

-- plugin detection -----------------------------------------------------

local function plugins()
  local ok, cfg = pcall(require, "lazy.core.config")
  return ok and cfg.plugins or {}
end

-- "vim-tmux-navigator" -> "tmuxnavigator", "oil.nvim" -> "oil"
local function norm(name)
  return (name:lower():gsub("%.nvim$", ""):gsub("^n?vim%-", ""):gsub("[^%w]", ""))
end

local function plugin_for_path(file)
  for name, p in pairs(plugins()) do
    if p.dir and vim.startswith(file, p.dir .. "/") then
      return name
    end
  end
end

local module_cache = {}
local function plugin_for_module(mod)
  local root = mod:match("^[^%.]+")
  if module_cache[root] == nil then
    module_cache[root] = false
    for name, p in pairs(plugins()) do
      if p.dir and (vim.uv.fs_stat(p.dir .. "/lua/" .. root) or vim.uv.fs_stat(p.dir .. "/lua/" .. root .. ".lua")) then
        module_cache[root] = name
        break
      end
    end
  end
  return module_cache[root] or nil
end

-- keys declared in lazy.nvim plugin specs (most LazyVim keys come from here)
local function key_owners()
  local owners = {}
  for name, p in pairs(plugins()) do
    local keys = p._ and p._.handlers and p._.handlers.keys
    for _, k in pairs(keys or {}) do
      local ok, lhs = pcall(function()
        return vim.fn.keytrans(vim.keycode(k.lhs))
      end)
      if ok then
        for _, mode in ipairs(type(k.mode) == "table" and k.mode or { k.mode or "n" }) do
          owners[(mode == "v" and "x" or mode) .. lhs] = name
        end
      end
    end
  end
  return owners
end

local files = {}
local function plugin_for_callback(fn)
  local info = debug.getinfo(fn, "S")
  if not info or info.source:sub(1, 1) ~= "@" then
    return nil
  end
  local file = info.source:sub(2)

  local owner = plugin_for_path(file)
  if owner and owner ~= "LazyVim" then
    return owner
  end

  -- defined in your config or LazyVim's keymaps: look at what the function uses
  if files[file] == nil then
    local ok, lines = pcall(vim.fn.readfile, file)
    files[file] = ok and lines or false
  end
  local lines = files[file]
  local body = (lines and info.linedefined > 0)
      and table.concat(vim.list_slice(lines, info.linedefined, info.lastlinedefined), "\n")
    or ""
  local mod = body:match("require%s*%(?%s*[\"']([%w_%.%-]+)[\"']")
  local from_mod = mod and plugin_for_module(mod)
  if from_mod and from_mod ~= "LazyVim" then
    return from_mod
  end
  if body:find("Snacks%.") and plugins()["snacks.nvim"] then
    return "snacks.nvim"
  end

  if owner then
    return owner
  end
  if vim.startswith(file, vim.fn.stdpath("config")) then
    return "Your config"
  end
  if vim.env.VIMRUNTIME and vim.startswith(file, vim.env.VIMRUNTIME) then
    return "Neovim (built-in)"
  end
end

-- "<cmd>Oil<cr>" -> oil.nvim, "<cmd>BufferLinePick<cr>" -> bufferline.nvim
local function plugin_for_command(rhs)
  local cmd = rhs:match("^<[Cc][Mm][Dd]>%s*(%a+)") or rhs:match("^:%s*(%a+)")
  if not cmd then
    return nil
  end
  cmd = cmd:lower()
  local best, best_score
  for name in pairs(plugins()) do
    local n = norm(name)
    local len = 0
    while len < #n and len < #cmd and n:byte(len + 1) == cmd:byte(len + 1) do
      len = len + 1
    end
    if len >= 4 or (len == #n and len >= 3) then
      local score = len + (len == #n and 100 or 0)
      if not best or score > best_score then
        best, best_score = name, score
      end
    end
  end
  return best
end

-- listing --------------------------------------------------------------

local function list()
  files = {}
  local owners = key_owners()
  local items, seen = {}, {}
  for _, mode in ipairs(modes) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local lhs = vim.fn.keytrans(m.lhsraw or m.lhs)
      local id = mode .. lhs
      if not seen[id] and not lhs:find("<Plug>") and not lhs:find("<SNR>") then
        seen[id] = true
        local ok, plugin = pcall(function()
          return owners[id] or (m.callback and plugin_for_callback(m.callback)) or (m.rhs and plugin_for_command(m.rhs))
        end)
        table.insert(items, {
          mode = mode,
          lhs = lhs,
          desc = m.desc or m.rhs or "(lua function)",
          plugin = (ok and plugin) or "Other",
        })
      end
    end
  end
  table.sort(items, function(a, b)
    return a.mode .. a.lhs < b.mode .. b.lhs
  end)
  return items
end

local function grouped()
  local groups = {}
  for _, item in ipairs(list()) do
    groups[item.plugin] = groups[item.plugin] or {}
    table.insert(groups[item.plugin], item)
  end
  return groups
end

-- UI helpers: <BS> on an empty field calls `back`, <Esc> closes -------------

local function select(items, opts, on_pick, back)
  -- fallback if snacks isn't available: plain vim.ui.select, cancel = back
  if not (_G.Snacks and Snacks.picker) then
    return vim.ui.select(
      items,
      opts,
      vim.schedule_wrap(function(item, idx)
        if item == nil then
          if back then
            back()
          end
          return
        end
        on_pick(item, idx)
      end)
    )
  end

  local format_item = opts.format_item or tostring
  local entries = {}
  for i, item in ipairs(items) do
    entries[i] = { idx = i, text = format_item(item), value = item }
  end

  Snacks.picker.pick({
    title = opts.prompt,
    items = entries,
    layout = { preset = "select" },
    sort = { fields = { "score:desc", "idx" } }, -- keep our order when not searching
    format = function(entry)
      return { { entry.text } }
    end,
    confirm = function(picker, entry)
      picker:close()
      if entry then
        vim.schedule(function()
          on_pick(entry.value, entry.idx)
        end)
      end
    end,
    actions = {
      go_back = function(picker)
        if vim.api.nvim_get_current_line() ~= "" then
          vim.api.nvim_feedkeys(vim.keycode("<BS>"), "n", false) -- normal backspace
          return
        end
        picker:close()
        if back then
          vim.schedule(back)
        end
      end,
    },
    win = { input = { keys = { ["<BS>"] = { "go_back", mode = { "i", "n" } } } } },
  })
end

local function input(opts, on_done, back, allow_empty)
  local prompt = vim.trim(opts.prompt or "Input")
  local default = opts.default or ""
  local width = math.min(vim.o.columns - 4, math.max(50, #prompt + 4, #default + 4))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.b[buf].completion = false -- no completion popup in this box
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = math.floor(vim.o.lines / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
  })
  vim.cmd("startinsert!")

  local function close()
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function text()
    return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  end
  local o = { buffer = buf, nowait = true }

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    local t = text()
    close()
    vim.schedule(function()
      if t == "" and not allow_empty then
        if back then
          back()
        end
        return
      end
      on_done(t)
    end)
  end, o)

  vim.keymap.set({ "i", "n" }, "<Esc>", close, o)

  vim.keymap.set("i", "<BS>", function()
    if text() ~= "" then
      return "<BS>"
    end
    vim.schedule(function()
      close()
      if back then
        back()
      end
    end)
    return ""
  end, vim.tbl_extend("force", o, { expr = true }))

  -- close if you click or jump away
  vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })
end

-- screens --------------------------------------------------------------

local function edit_keymap(item, back)
  local function again()
    edit_keymap(item, back)
  end
  select({ "Change key", "Change description", "Disable" }, { prompt = item.mode .. "  " .. item.lhs }, function(choice)
    if choice == "Change key" then
      input({ prompt = "New key for " .. item.lhs .. " (e.g. <leader>o): " }, function(to)
        local existing = get(item.mode, to)
        if existing then
          local what = existing.desc or existing.rhs or "a function"
          if vim.fn.confirm(to .. " is already mapped to: " .. what .. "\nOverwrite?", "&Yes\n&No", 2) ~= 1 then
            return again()
          end
        end
        save({ action = "rebind", mode = item.mode, from = item.lhs, to = to })
        back()
      end, again)
    elseif choice == "Change description" then
      input({ prompt = "Description: ", default = item.desc }, function(desc)
        save({ action = "desc", mode = item.mode, lhs = item.lhs, desc = desc })
        back()
      end, again)
    elseif choice == "Disable" then
      save({ action = "disable", mode = item.mode, lhs = item.lhs })
      back()
    end
  end, back)
end

local function show_keymaps(title, get_items, back, show_plugin)
  local function reopen()
    show_keymaps(title, get_items, back, show_plugin)
  end
  local items = get_items()
  if #items == 0 then
    vim.notify("keymap-editor: no keymaps here")
    return back()
  end
  select(items, {
    prompt = title,
    format_item = function(i)
      local line = string.format("%-2s %-20s %s", i.mode, i.lhs, i.desc)
      return show_plugin and (line .. "  [" .. i.plugin .. "]") or line
    end,
  }, function(item)
    edit_keymap(item, reopen)
  end, back)
end

local function browse_plugins(back)
  local function reopen()
    browse_plugins(back)
  end
  local groups = grouped()
  local names = vim.tbl_keys(groups)
  table.sort(names, function(a, b)
    if (a == "Other") ~= (b == "Other") then
      return b == "Other"
    end -- "Other" last
    return a:lower() < b:lower()
  end)
  select(names, {
    prompt = "Keymaps by plugin",
    format_item = function(name)
      return string.format("%-30s %d", name, #groups[name])
    end,
  }, function(name)
    show_keymaps(name, function()
      return grouped()[name] or {}
    end, reopen)
  end, back)
end

local function add_new(back)
  local function step_mode()
    select(modes, { prompt = "Mode" }, function(mode)
      local function step_key()
        input({ prompt = "Key (e.g. <leader>o): " }, function(lhs)
          local function step_rhs()
            input({ prompt = "Action (e.g. <cmd>Lazy<cr>): " }, function(rhs)
              input({ prompt = "Description (optional): " }, function(desc)
                save({ action = "add", mode = mode, lhs = lhs, rhs = rhs, desc = desc ~= "" and desc or nil })
                back()
              end, step_rhs, true)
            end, step_key)
          end
          step_rhs()
        end, step_mode)
      end
      step_key()
    end, back)
  end
  step_mode()
end

local function remove_change(back)
  local data = read()
  if #data == 0 then
    vim.notify("keymap-editor: no saved changes")
    return back()
  end
  select(data, {
    prompt = "Remove a saved change",
    format_item = function(o)
      local key = o.lhs or (o.from .. " -> " .. o.to)
      return string.format("%-8s %-2s %s %s", o.action, o.mode, key, o.desc or "")
    end,
  }, function(_, idx)
    table.remove(data, idx)
    write(data)
    vim.notify("keymap-editor: change removed. Restart Neovim to restore the original mapping.")
    remove_change(back)
  end, back)
end

function M.open()
  select({
    "Browse by plugin",
    "Browse all keymaps",
    "Add a keymap",
    "Remove a saved change",
    "Open keymaps.json",
  }, { prompt = "Keymap editor (BS = back, Esc = close)" }, function(choice)
    if choice == "Browse by plugin" then
      browse_plugins(M.open)
    elseif choice == "Browse all keymaps" then
      show_keymaps("All keymaps", list, M.open, true)
    elseif choice == "Add a keymap" then
      add_new(M.open)
    elseif choice == "Remove a saved change" then
      remove_change(M.open)
    elseif choice == "Open keymaps.json" then
      vim.cmd.edit(path)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("KeymapEditor", M.open, { desc = "Open keymap editor" })

  local group = vim.api.nvim_create_augroup("keymap_editor", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "VeryLazy", "LazyLoad" },
    callback = function()
      vim.schedule(M.apply)
    end,
  })
end

return M
