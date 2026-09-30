-- Register the column with default settings, so that adding the column name to
-- oil's `columns` list is enough to make it show up. A `setup()` call from the
-- user's config runs earlier and wins; this only fills in the defaults.
if vim.g.loaded_voil then
  return
end
vim.g.loaded_voil = true

if not vim.g.voil_setup then
  require("voil").setup()
end
