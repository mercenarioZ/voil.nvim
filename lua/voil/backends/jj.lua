---@type Voil.Backend
return {
  name = "jj",
  cmd = { "jj", "diff", "--summary" },
  detect = function(dir)
    return vim.fs.find(".jj", { upward = true, path = dir, type = "directory" })[1] ~= nil
  end,
  parse = function(stdout)
    local changes = {}
    for _, line in ipairs(vim.split(stdout, "\n", { plain = true })) do
      -- "<CODE> path", a rename reads "R {old => new}"
      local code, path = line:match("^(%a) (.+)$")
      if code then
        if path:sub(1, 1) == "{" then
          path = path:match("=> ([^}]+)") or path
        end
        changes[#changes + 1] = { path = path, code = code }
      end
    end
    return changes
  end,
}
