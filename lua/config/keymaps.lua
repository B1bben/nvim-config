-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

-- Scrolling / searching (keep cursor centered)
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })
map("n", "n", "nzzzv", { desc = "Next match (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev match (centered)" })

-- Editing
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking" })
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Explorer (oil)
map("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
map("n", "<leader>e", "<cmd>Oil<cr>", { desc = "Explorer (current file's dir)" })
map("n", "<leader>E", function()
  require("oil").open(vim.fn.getcwd())
end, { desc = "Explorer (cwd)" })

-- Buffers (bufferline)
for i = 1, 8 do
  map("n", "<A-" .. i .. ">", "<cmd>BufferLineGoToBuffer " .. i .. "<cr>", { desc = "Go to buffer " .. i })
end
map("n", "<A-9>", "<cmd>BufferLineGoToBuffer -1<cr>", { desc = "Go to last buffer" })
map("n", "<leader>bj", "<cmd>BufferLinePick<cr>", { desc = "Pick buffer" })

-- Undotree
map("n", "<leader>U", "<cmd>UndotreeToggle<cr>", { desc = "Undotree" })

-- tmux navigator (uncomment if you enabled the plugin)
-- map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Navigate left" })
-- map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "Navigate down" })
-- map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "Navigate up" })
-- map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "Navigate right" })

-- Keymap editor
map("n", "<leader>k", "<cmd>KeymapEditor<cr>", { desc = "Keymap editor" })
