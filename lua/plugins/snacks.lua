return {
  "folke/snacks.nvim",
  opts = {
    explorer = { enabled = false },
  },
  keys = {
    -- remove LazyVim's explorer mappings so oil can use them
    { "<leader>e", false },
    { "<leader>E", false },
    { "<leader>fe", false },
    { "<leader>fE", false },
  },
}
