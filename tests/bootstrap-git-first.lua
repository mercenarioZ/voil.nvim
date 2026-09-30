-- Used by the `gitfirst` case: in a colocated repo git and jj both have markers,
-- so the order decides which one is authoritative.
require("voil").setup({
  backends = { "git", "jj" },
})
