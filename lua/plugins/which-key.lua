return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    -- wait 300ms before showing the popup (if you know the key, it never appears)
    opts.delay = 300

    -- remove the icons next to each entry
    opts.icons = vim.tbl_deep_extend("force", opts.icons or {}, { mappings = false })

    -- hide entries from the menu (the keys still work, they just aren't listed)
    opts.spec = opts.spec or {}
    vim.list_extend(opts.spec, {
      { "<leader>L", hidden = true }, -- LazyVim changelog
      { "<leader>K", hidden = true }, -- keywordprg
      { "<leader>`", hidden = true }, -- duplicate of <leader>bb
      { "<leader>-", hidden = true }, -- split below (also under <leader>w)
      { "<leader>|", hidden = true }, -- split right (also under <leader>w)
      { "<leader>.", hidden = true }, -- scratch buffer
      { "<leader>S", hidden = true }, -- select scratch buffer
    })
  end,
}
