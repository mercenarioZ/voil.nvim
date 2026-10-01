-- One case per nvim process; tests/run.sh picks the case and builds fixtures.
local voil = require("voil")

local repo_git = assert(vim.env.FIXTURE_GIT, "FIXTURE_GIT is not set")
local repo_jj = vim.env.FIXTURE_JJ

local M = {}

local buf

local function live()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "oil" then
      buf = b
      return b
    end
  end
  error("no live oil buffer")
end

local function open(dir)
  vim.cmd("Oil " .. vim.fn.fnameescape(dir))
  buf = vim.api.nvim_get_current_buf()
end

---@return table<string, string> listing entry name -> text drawn in the column
local function codes()
  local out = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(live(), 0, -1, true)) do
    local parts = vim.split(line, "%s+", { trimempty = true })
    if #parts >= 2 then
      out[parts[#parts]] = parts[#parts - 1]
    end
  end
  return out
end

---@param want table<string, string> entry name -> expected column text, "-" means clean
local function expect(want)
  local settled = vim.wait(10000, function()
    local got = codes()
    for name, code in pairs(want) do
      if got[name] ~= code then
        return false
      end
    end
    return true
  end, 100)
  local got = codes()
  if not settled then
    print("listing:")
    print(table.concat(vim.api.nvim_buf_get_lines(live(), 0, -1, true), "\n"))
    print("parsed: " .. vim.inspect(got))
    print("wanted: " .. vim.inspect(want))
  end
  assert(settled, "the column never settled")
  for name, code in pairs(want) do
    assert(got[name] == code, ("%s: expected %q, got %q"):format(name, code, tostring(got[name])))
  end
end

local function assert_filename_group(name, group)
  local bufnr = live()
  local namespace = vim.api.nvim_get_namespaces().Oil
  assert(namespace, "Oil highlight namespace is missing")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  for row, line in ipairs(lines) do
    local start = line:find(name, 1, true)
    if start then
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, namespace, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
        local details = mark[4]
        if details and details.hl_group == group and mark[3] <= start - 1 and details.end_col >= start - 1 then
          return
        end
      end
    end
  end
  error(("%s does not use %s"):format(name, group))
end


local function write_file(path)
  vim.cmd("vsplit " .. vim.fn.fnameescape(path))
  vim.cmd("normal! Gox")
  vim.cmd("write")
end

M.git = function()
  open(repo_git)
  expect({ ["dirty.txt"] = "M", ["untracked.txt"] = "?", ["keep.txt"] = "-", ["sub/"] = "M" })
end

M.jj = function()
  open(repo_jj)
  expect({
    ["dirty.txt"] = "M",
    ["added.txt"] = "A",
    ["renamed.txt"] = "R",
    ["keep.txt"] = "-",
    ["sub/"] = "M",
  })
end

M.subdir = function()
  open(repo_jj .. "/sub")
  -- changes outside the listed directory must not leak in
  expect({ ["change.txt"] = "M", ["keep.txt"] = "-", ["../"] = "-" })
end

M.write = function()
  open(repo_jj)
  expect({ ["keep.txt"] = "-" })

  write_file(repo_jj .. "/keep.txt")
  expect({ ["keep.txt"] = "M" })

  -- a write below the listing updates the directory that contains it
  write_file(repo_jj .. "/docs/nested.txt")
  expect({ ["docs/"] = "A" })
end

M.failure = function()
  local notified = {}
  local notify = vim.notify
  vim.notify = function(msg, level, opts)
    notified[#notified + 1] = tostring(msg)
    return notify(msg, level, opts)
  end

  local path = vim.env.PATH
  vim.env.PATH = "/nonexistent"

  open(repo_git)
  vim.wait(1500)
  assert(notified[1], "a failing backend must warn")
  assert(notified[1]:match("voil: git failed"), notified[1])
  -- unknown is not the same as clean, but the listing itself must survive
  assert(codes()["dirty.txt"], "the listing broke when the command failed")

  vim.env.PATH = path
  write_file(repo_git .. "/keep.txt")
  expect({ ["dirty.txt"] = "M", ["keep.txt"] = "M" })
end

M.config = function()
  assert(voil.config.column == "vcs", voil.config.column)
  open(repo_git)
  expect({ ["dirty.txt"] = "\u{271a}", ["untracked.txt"] = "?", ["keep.txt"] = "-" })

  -- oil parses every line on write, so the column must stay parseable
  local _, errors = require("oil.mutator.parser").parse(live())
  assert(#errors == 0, vim.inspect(errors))

  write_file(repo_git .. "/parsed.txt")
  vim.wait(1500)
  assert(vim.fn.filereadable(repo_git .. "/parsed.txt") == 1, "writes through oil stopped working")
end

M.highlight = function()
  for _, group in ipairs({ "VoilModified", "VoilAdded", "VoilDeleted", "VoilUntracked" }) do
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    assert(hl.fg, group .. " has no foreground color")
    assert(hl.bold, group .. " is not bold")
  end

  vim.cmd.colorscheme("default")
  local after = vim.api.nvim_get_hl(0, { name = "VoilModified", link = false })
  assert(after.fg, "colors were lost after a colorscheme switch")
end

M.filename_highlight = function()
  open(repo_git)
  expect({ ["dirty.txt"] = "M", ["untracked.txt"] = "?" })
  assert_filename_group("dirty.txt", "VoilModified")
  assert_filename_group("untracked.txt", "VoilUntracked")
end

M.noncolocated = function()
  local repo = assert(vim.env.FIXTURE_JJ_PLAIN, "FIXTURE_JJ_PLAIN is not set")
  -- no .git anywhere: only a jj backend can answer here
  assert(vim.fn.isdirectory(repo .. "/.git") == 0, "fixture must not be colocated")
  assert(voil.detect_backend(repo .. "/").name == "jj", "jj should own this directory")
  open(repo)
  expect({ ["dirty.txt"] = "M", ["added.txt"] = "A", ["renamed.txt"] = "R", ["keep.txt"] = "-" })
end

M.gitfirst = function()
  -- a filesystem rename that jj has not snapshotted yet: git reports it as
  -- delete + untracked, jj reports one rename. The backend order picks which
  -- answer the column shows.
  assert(voil.config.backends[1] == "git", vim.inspect(voil.config.backends))
  assert(voil.detect_backend(repo_jj .. "/").name == "git", "git should win the detection")
  open(repo_jj)
  expect({ ["renamed.txt"] = "?", ["added.txt"] = "?", ["dirty.txt"] = "M" })
end

local case = assert(vim.env.CASE, "CASE is not set")
local fn = M[case] or error("unknown case: " .. case)

local ok, err = pcall(fn)
if ok then
  print("PASS " .. case)
else
  print("FAIL " .. case .. ": " .. tostring(err))
end
vim.cmd(ok and "qa!" or "cq")
