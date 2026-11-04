-- Your settings in one place.
-- Anything changed via :Settings (or <leader>U) is saved separately and wins over these.
-- `:Settings reset` / `:Settings reset <name>` goes back to the values below.
return {
  colorscheme = "tokyonight", -- also try "catppuccin" (both are installed)

  -- vim.opt.<name> = value
  options = {
    relativenumber = true,
    wrap = false,
    scrolloff = 8,
    tabstop = 2,
    shiftwidth = 2,
    spell = false,
    cursorline = true,
  },

  -- vim.g.<name> = value (LazyVim reads several of these)
  globals = {
    autoformat = true, -- format on save
    snacks_animate = true, -- UI animations
  },

  -- Plugin overrides, merged into LazyVim's specs.
  --   true/false  -> enable/disable the plugin
  --   table       -> any lazy.nvim spec fields (opts, keys, event, ...)
  plugins = {
    -- ["folke/tokyonight.nvim"] = { opts = { style = "night", transparent = false } },
    -- ["akinsho/bufferline.nvim"] = { opts = { options = { always_show_bufferline = true } } },
    -- ["folke/flash.nvim"] = false,
    -- ["ellisonleao/gruvbox.nvim"] = true, -- add a new plugin
  },
  -- Short explanations shown in the :Settings menu and info window.
  -- Add a line here for any setting you add.
  descriptions = {
    colorscheme = "The color theme for the editor",
    relativenumber = "Show line numbers relative to the cursor (handy for 5j / 3k jumps)",
    wrap = "Soft-wrap long lines instead of scrolling sideways",
    scrolloff = "Keep this many lines visible above/below the cursor",
    tabstop = "How many columns a <Tab> character is displayed as",
    shiftwidth = "Indent size used by >>, << and auto-indent",
    spell = "Underline misspelled words",
    cursorline = "Highlight the line the cursor is on",
    autoformat = "LazyVim: format the file automatically on save",
    snacks_animate = "Snacks: animate scrolling, resizing and other UI",
  },
}
