-- Config behind the demo image in the README: oil plus voil, nothing else.
--
--   VOIL_ROOT        this repository
--   OIL_NVIM_PATH    oil.nvim
--   DEMO_DIR         directory to list
--   DEMO_RTP         optional extra runtimepath entries (colorscheme, icons)
--   DEMO_COLORSCHEME optional, defaults to "default"
local function prepend(path)
  if path and path ~= "" then
    vim.opt.runtimepath:prepend(path)
  end
end

prepend(vim.env.VOIL_ROOT)
prepend(vim.env.OIL_NVIM_PATH)
for dir in (vim.env.DEMO_RTP or ""):gmatch("[^,]+") do
  prepend(dir)
end

vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.cursorline = true
vim.opt.laststatus = 0
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.shortmess:append("F")

pcall(function()
  require("mini.icons").setup()
  require("mini.icons").mock_nvim_web_devicons()
end)

require("oil").setup({
  columns = { "voil" },
  view_options = {
    show_hidden = true,
    is_always_hidden = function(name)
      return name == ".git" or name == ".jj"
    end,
  },
})

local ok, err = pcall(vim.cmd.colorscheme, vim.env.DEMO_COLORSCHEME or "default")
if not ok then
  vim.notify(tostring(err), vim.log.levels.WARN)
end

vim.cmd("Oil " .. vim.fn.fnameescape(assert(vim.env.DEMO_DIR)))
