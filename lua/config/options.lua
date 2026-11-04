-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
require("settings").setup()
local opt = vim.opt
opt.scrolloff = 8
opt.colocolumn = "120"
opt.wrap = false
opt.swapfile = false
opt.undofile = true
