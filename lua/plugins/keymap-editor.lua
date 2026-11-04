return {
  name = "keymap-editor",
  dir = vim.fn.stdpath("config") .. "/local/keymap-editor",
  lazy = false, -- needs to load at startup to re-apply your saved changes
  config = function()
    require("keymap_editor").setup()
  end,
}
