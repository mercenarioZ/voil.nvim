-- Used by the `config` case: rename the column and give it a custom symbol.
require("voil").setup({
  column = "vcs",
  symbols = { M = "\u{271a}" }, -- ✚
})

vim.env.OIL_COLUMNS = "icon,vcs"
