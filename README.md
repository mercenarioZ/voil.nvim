# voil.nvim

Version control status, in [oil.nvim](https://github.com/stevearc/oil.nvim) itself.

voil adds one column to the oil listing with the state of each entry, from **jj**
or **git**. A directory whose contents changed carries the most severe status of
its children.

```
  /002 M sub/
  /005 A added.txt
  /006 - clean.txt
  /001 M dirty.txt
  /003 R renamed.txt
```

`M` modified, `A` added, `D` deleted, `R` renamed, `C` copied, `?` untracked,
`!` ignored, `-` clean.

## Why another one

The existing oil status plugins draw signs in the sign column. voil registers a
real column through oil's own column registry instead, so it lines up with the
rest of the listing, works with `align` like any other column, and stays
readable without a sign column.

It also speaks jj, which matters if jj owns the repository: `git status` in a
jj-colocated repo reflects the git index, not what `jj diff` reports.

No dependencies beyond oil.nvim. No sign column. One process per directory,
cached, with a backoff when the command fails.

## Requirements

- Neovim >= 0.10 (`vim.system`)
- [oil.nvim](https://github.com/stevearc/oil.nvim)
- `git` and/or `jj` in `$PATH`

## Install

lazy.nvim:

```lua
{
  "mercenarioZ/voil.nvim",
  dependencies = { "stevearc/oil.nvim" },
  opts = {},
}
```

vim.pack (Neovim 0.12):

```lua
vim.pack.add({
  { src = "https://github.com/stevearc/oil.nvim" },
  { src = "https://github.com/mercenarioZ/voil.nvim" },
})
require("voil").setup()
```

Then add the column to oil:

```lua
require("oil").setup({
  columns = { "icon", "voil", "mtime" },
})
```

The plugin registers the column with default options at startup, so adding the
name to `columns` is enough. Call `setup()` when you want to change something.

## Configuration

```lua
require("voil").setup({
  -- name the column is registered under in oil
  column = "voil",
  -- tried in order, the first backend whose marker exists wins
  backends = { "jj", "git" },
  -- status code -> text drawn in the column (no whitespace: oil parses the
  -- column back out of the line on write)
  symbols = { M = "~", ["?"] = "!" },
  -- status code -> { group, base, plain }
  highlight = {
    M = { group = "VoilModified", base = "DiagnosticWarn" },
    A = { group = "VoilAdded", base = "Added" },
    D = { group = "VoilDeleted", base = "Removed" },
    R = { group = "VoilRenamed", base = "Changed" },
    C = { group = "VoilCopied", base = "Changed" },
    ["?"] = { group = "VoilUntracked", base = "DiagnosticHint" },
    ["!"] = { group = "VoilIgnored", base = "Comment", plain = true },
  },
  -- warn once per failure spell when the command fails
  notify_on_error = true,
  -- milliseconds before a directory whose command failed is fetched again
  retry_ms = 5000,
  -- refetch after writing a file below a listed directory
  refresh_on_write = true,
  -- refetch after oil applies file operations
  refresh_on_mutation = true,
})
```

The foreground of each highlight group is copied from a group the colorscheme
already colors. `link` cannot add attributes, and the diff groups
(`DiffAdd`/`DiffChange`/`DiffDelete`) only carry a background, which makes a one
character column invisible on a normal listing line. Colors are re-derived on
`ColorScheme`.

## Backends

A backend is four fields:

```lua
require("voil").register_backend({
  name = "svn",
  cmd = { "svn", "status", "." }, -- run with the directory as cwd
  detect = function(dir)
    return vim.fs.find(".svn", { upward = true, path = dir })[1] ~= nil
  end,
  ---@return { path: string, code: string }[]
  parse = function(stdout)
    local changes = {}
    for _, line in ipairs(vim.split(stdout, "\n", { plain = true })) do
      local code, path = line:match("^(%a)%s+(.+)$")
      if code then
        changes[#changes + 1] = { path = path, code = code }
      end
    end
    return changes
  end,
})
```

Paths are relative to the listed directory. Paths outside it (jj reports
`../foo`) are dropped, and anything deeper is collapsed onto the directory that
contains it, keeping the most severe code: `D > M > R > C > A > ? > !`.

## API

```lua
local voil = require("voil")

voil.setup(opts)         -- configure
voil.refresh(dir?)       -- refetch, redraw; no argument means every tracked dir
voil.get_status(dir)     -- { [entry name] = code } or nil before the first fetch
voil.register_backend(b) -- add a backend
```

The column is read only, so oil cannot sort by it.

## How it works

oil calls a column's `render` synchronously while drawing the buffer, so voil
keeps a per-directory cache and answers from it. A miss starts an async
`jj diff --summary` or `git status --short`, and when the answer lands the open
oil buffers are rerendered with `oil.view.render_buffer_async`. Rerendering
discards unsaved edits, so a buffer with pending changes is left alone.

A failed command does not look like a clean tree: the directory stays unknown,
the user is warned once, and the directory is retried after `retry_ms`.
Refetching happens when a directory is entered, after oil applies file
operations, and after writing a file below a listed directory.

## Tests

```sh
bash tests/run.sh          # OIL_NVIM_PATH=... to point at a specific oil.nvim
VERBOSE=1 bash tests/run.sh
```

Every case gets a throwaway git and jj repository, and the jj cases are skipped
when jj is not installed.

## Limitations

- Uses parts of oil that are not in its documented API (`oil.columns`,
  `oil.constants`, `oil.view`). If a future oil release changes them, the column
  stays empty; `:messages` says why.
- Local filesystem only: remote oil schemes have no working copy to inspect.
- Rename detection is whatever the backend reports. jj reports a rename as one
  entry; git only when it notices the rename.
- Hidden files are unaffected, but ignored files only show up if the backend
  reports them (git needs `--ignored`; voil does not pass it).

## Alternatives

- [refractalize/oil-git-status.nvim](https://github.com/refractalize/oil-git-status.nvim)
  - git only, draws two sign columns
- [SirZenith/oil-vcs-status](https://github.com/SirZenith/oil-vcs-status)
  - git and svn, draws a sign column
- [malewicz1337/oil-git.nvim](https://github.com/malewicz1337/oil-git.nvim)
  - git only, highlights and symbols

## License

MIT
