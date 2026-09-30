local aggregate = require("voil.aggregate")
local constants = require("oil.constants")
local highlight = require("voil.highlight")
local oil = require("oil")

local FIELD_NAME = constants.FIELD_NAME

local M = {}

---@class Voil.Highlight
---@field group string Highlight group to define
---@field base string Highlight group to copy the foreground from
---@field plain nil|boolean Skip the bold attribute

---@class Voil.Change
---@field path string Path relative to the directory being listed
---@field code string One character status code

---@class Voil.Backend
---@field name string
---@field cmd string[] Command that runs with the directory as cwd
---@field detect fun(dir: string): boolean
---@field parse fun(stdout: string): Voil.Change[]

---@class Voil.Config
---@field column string Name the column is registered under in oil
---@field backends string[] Backend names in detection order
---@field symbols table<string, string> Status code to displayed text
---@field highlight table<string, Voil.Highlight>
---@field notify_on_error boolean Warn when the underlying command fails
---@field retry_ms integer Backoff before a failed directory is fetched again
---@field refresh_on_write boolean Refresh after writing a file below a listed directory
---@field refresh_on_mutation boolean Refresh after oil applies file operations

---@type Voil.Config
local default_config = {
  column = "voil",
  backends = { "jj", "git" },
  symbols = {},
  highlight = {
    M = { group = "VoilModified", base = "DiagnosticWarn" },
    A = { group = "VoilAdded", base = "Added" },
    D = { group = "VoilDeleted", base = "Removed" },
    R = { group = "VoilRenamed", base = "Changed" },
    C = { group = "VoilCopied", base = "Changed" },
    ["?"] = { group = "VoilUntracked", base = "DiagnosticHint" },
    ["!"] = { group = "VoilIgnored", base = "Comment", plain = true },
  },
  notify_on_error = true,
  retry_ms = 5000,
  refresh_on_write = true,
  refresh_on_mutation = true,
}

M.config = vim.deepcopy(default_config)

local backends = {}
---@type Voil.Backend[]
local enabled = {}

-- dir -> { [entry name] = code }; a missing key means "not fetched yet"
local cache = {}
local inflight = {}
-- every dir we ever tried to fetch, including the ones whose fetch failed
local tracked = {}
-- dir -> time before which a failed fetch is not retried
local retry_at = {}

---Register a backend so that it can be named in the `backends` option.
---@param backend Voil.Backend
M.register_backend = function(backend)
  backends[backend.name] = backend
end

M.register_backend(require("voil.backends.git"))
M.register_backend(require("voil.backends.jj"))

---@param dir string
---@return nil|Voil.Backend
M.detect_backend = function(dir)
  for _, backend in ipairs(enabled) do
    if backend.detect(dir) then
      return backend
    end
  end
end

---@param dir string
---@return nil|table<string, string> nil until the first fetch of that dir finishes
M.get_status = function(dir)
  return cache[dir]
end

---A failed fetch is not the same as a clean tree: leave the directory unknown,
---tell the user once per failure spell, and retry after a short backoff.
---@param dir string
---@param backend string
---@param reason string
local function report_failure(dir, backend, reason)
  local first = retry_at[dir] == nil
  retry_at[dir] = vim.uv.now() + M.config.retry_ms
  if first and M.config.notify_on_error then
    vim.schedule(function()
      vim.notify(
        ("voil: %s failed in %s: %s"):format(backend, dir, vim.trim(reason)),
        vim.log.levels.WARN
      )
    end)
  end
  vim.schedule(M.render)
end

---Fetch the status of a directory.
---@param dir string
---@param force nil|boolean Refetch even if the last attempt failed just now
M.load = function(dir, force)
  tracked[dir] = true
  if inflight[dir] then
    return
  end
  if not force and retry_at[dir] and vim.uv.now() < retry_at[dir] then
    return
  end
  local backend = M.detect_backend(dir)
  if not backend then
    cache[dir] = {}
    return
  end
  inflight[dir] = true
  -- vim.system throws when the binary is missing, so a broken PATH or a
  -- vanished cwd must not take the oil listing down with it
  local spawned, spawn_err = pcall(vim.system, backend.cmd, { cwd = dir, text = true }, function(res)
    inflight[dir] = nil
    if res.code ~= 0 then
      report_failure(dir, backend.name, res.stderr or ("exit code " .. res.code))
      return
    end
    retry_at[dir] = nil
    cache[dir] = aggregate.to_entries(backend.parse(res.stdout))
    vim.schedule(M.render)
  end)
  if not spawned then
    inflight[dir] = nil
    report_failure(dir, backend.name, tostring(spawn_err))
  end
end

---Rerender the oil buffers showing statuses we already know.
M.render = function()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- oil deletes hidden buffers after cleanup_delay_ms, so re-check liveness
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      if vim.bo[bufnr].filetype == "oil" then
        local dir = oil.get_current_dir(bufnr)
        -- rerendering throws away unsaved edits; never do that behind the user's back
        if dir and cache[dir] and not vim.bo[bufnr].modified then
          require("oil.view").render_buffer_async(bufnr, { refetch = false })
        end
      end
    end
  end
end

---Refetch and redraw. Without a directory every tracked directory is refetched.
---@param dir nil|string
M.refresh = function(dir)
  local dirs = dir and { dir } or vim.tbl_keys(tracked)
  for _, d in ipairs(dirs) do
    cache[d] = nil
    retry_at[d] = nil
    M.load(d, true)
  end
  M.render()
end

---@param opts nil|Voil.Config
M.setup = function(opts)
  vim.g.voil_setup = true
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})

  enabled = {}
  for _, name in ipairs(M.config.backends) do
    local backend = backends[name]
    if backend then
      enabled[#enabled + 1] = backend
    else
      vim.notify(("voil: unknown backend '%s'"):format(name), vim.log.levels.WARN)
    end
  end

  highlight.define(M.config.highlight)

  -- a column render must be synchronous, so it reads this cache and the fetch
  -- that fills it redraws the buffer once the answer lands
  require("oil.columns").register(M.config.column, {
    render = function(entry, _, bufnr)
      local name = entry[FIELD_NAME]
      if name == ".." then
        return ""
      end
      local dir = oil.get_current_dir(bufnr)
      if not dir then
        return ""
      end
      local status = cache[dir]
      if not status then
        M.load(dir)
        return ""
      end
      local code = status[name]
      if not code then
        return ""
      end
      local spec = M.config.highlight[code]
      return { M.config.symbols[code] or code, spec and spec.group }
    end,

    -- oil parses every line of the buffer, so consume the column's own text
    parse = function(line)
      return line:match("^(%S+)%s+(.*)$")
    end,
  })

  local augroup = vim.api.nvim_create_augroup("voil", { clear = true })

  -- colors are copied out of the colorscheme, so redo that on every switch
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      highlight.define(M.config.highlight)
    end,
  })

  -- entering a directory refetches it without emptying the cache first, so the
  -- column never flickers back to "-"
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "OilEnter",
    callback = function(args)
      local dir = oil.get_current_dir(args.data.buf)
      if dir then
        M.load(dir, true)
      end
    end,
  })

  if M.config.refresh_on_mutation then
    vim.api.nvim_create_autocmd("User", {
      group = augroup,
      pattern = "OilMutationComplete",
      callback = function()
        M.refresh()
      end,
    })
  end

  if M.config.refresh_on_write then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      callback = function(args)
        local path = vim.api.nvim_buf_get_name(args.buf)
        -- a write can change the status of every directory above it;
        -- oil.get_current_dir keeps a trailing slash, so compare prefixes directly
        for dir in pairs(tracked) do
          if path:sub(1, #dir) == dir then
            M.refresh(dir)
          end
        end
      end,
    })
  end
end

return M
