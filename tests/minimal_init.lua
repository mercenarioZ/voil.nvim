-- Minimal init for the test suite: this plugin plus oil.nvim, nothing else.
local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.runtimepath:prepend(root)

local function oil_path()
  if vim.env.OIL_NVIM_PATH and vim.env.OIL_NVIM_PATH ~= "" then
    return vim.env.OIL_NVIM_PATH
  end
  local candidates = {}
  vim.list_extend(candidates, vim.fn.globpath(vim.o.packpath, "pack/*/opt/oil.nvim", false, true))
  vim.list_extend(candidates, vim.fn.globpath(vim.o.packpath, "pack/*/start/oil.nvim", false, true))
  vim.list_extend(candidates, vim.fn.glob(vim.fn.stdpath("data") .. "/lazy/oil.nvim", false, true))
  return candidates[1]
end

local oil = oil_path()
if not oil then
  io.stderr:write("oil.nvim not found: set OIL_NVIM_PATH or install oil.nvim\n")
  vim.cmd("cq")
end
vim.opt.runtimepath:prepend(oil)

-- plugin/voil.lua already registered the column with the default options, so a
-- case that wants different ones reconfigures before oil reads its columns
if vim.env.VOIL_BOOTSTRAP and vim.env.VOIL_BOOTSTRAP ~= "" then
  dofile(vim.env.VOIL_BOOTSTRAP)
end

require("oil").setup({
  columns = vim.split(vim.env.OIL_COLUMNS or "icon,voil", ",", { plain = true }),
  view_options = { show_hidden = true },
})
