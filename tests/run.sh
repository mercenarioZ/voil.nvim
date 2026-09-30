#!/usr/bin/env bash
# Test suite for voil.nvim.
#
# Needs: neovim (>= 0.10) and git. jj is required for the jj cases; those are
# skipped when it is missing. Every case gets its own throwaway repo, so cases
# can write, rename and break things as much as they like.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

find_oil() {
  if [ -n "${OIL_NVIM_PATH:-}" ]; then
    echo "$OIL_NVIM_PATH"
    return
  fi
  for candidate in "$HOME"/.local/share/nvim/site/pack/*/opt/oil.nvim \
    "$HOME"/.local/share/nvim/site/pack/*/start/oil.nvim \
    "$HOME"/.local/share/nvim/lazy/oil.nvim; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  echo "cloning oil.nvim into $work" >&2
  git clone --depth 1 https://github.com/stevearc/oil.nvim "$work/oil.nvim" >/dev/null 2>&1
  echo "$work/oil.nvim"
}
export OIL_NVIM_PATH="$(find_oil)"

# git fixture: one modified file, one untracked file, a clean file, and a
# directory whose only change is a modified file inside it
init_git_repo() {
  local repo="$1"
  mkdir -p "$repo/sub"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@voil.invalid"
  git -C "$repo" config user.name "voil tests"
  printf 'v1\n' >"$repo/dirty.txt"
  printf 'keep\n' >"$repo/keep.txt"
  printf 'v1\n' >"$repo/sub/change.txt"
  printf 'keep\n' >"$repo/sub/keep.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  printf 'v2\n' >"$repo/dirty.txt"
  printf 'new\n' >"$repo/untracked.txt"
  printf 'v2\n' >"$repo/sub/change.txt"
}

# jj fixture: adds a rename and a directory that stays clean, so a nested write
# can be observed on its own
init_jj_repo() {
  local repo="$1"
  mkdir -p "$repo/sub" "$repo/docs"
  (cd "$repo" && jj git init --colocate >/dev/null 2>&1)
  printf 'v1\n' >"$repo/dirty.txt"
  printf 'old\n' >"$repo/old.txt"
  printf 'keep\n' >"$repo/keep.txt"
  printf 'v1\n' >"$repo/sub/change.txt"
  printf 'keep\n' >"$repo/sub/keep.txt"
  printf 'keep\n' >"$repo/docs/keep.md"
  (cd "$repo" && jj commit -m init >/dev/null 2>&1)
  printf 'v2\n' >"$repo/dirty.txt"
  printf 'new\n' >"$repo/added.txt"
  mv "$repo/old.txt" "$repo/renamed.txt"
  printf 'v2\n' >"$repo/sub/change.txt"
}

have_jj=0
if command -v jj >/dev/null 2>&1; then
  have_jj=1
fi

# same content as the colocated fixture, but without a .git directory: the case
# proves that a git-only implementation cannot answer here
init_jj_repo_plain() {
  local repo="$1"
  mkdir -p "$repo/sub"
  # --no-colocate: a user config can turn colocation on by default
  (cd "$repo" && jj git init --no-colocate >/dev/null 2>&1)
  printf 'v1\n' >"$repo/dirty.txt"
  printf 'old\n' >"$repo/old.txt"
  printf 'keep\n' >"$repo/keep.txt"
  printf 'v1\n' >"$repo/sub/change.txt"
  (cd "$repo" && jj commit -m init >/dev/null 2>&1)
  printf 'v2\n' >"$repo/dirty.txt"
  printf 'new\n' >"$repo/added.txt"
  mv "$repo/old.txt" "$repo/renamed.txt"
}

failures=0
run() {
  local case="$1" bootstrap="${2:-}"
  local out

  export FIXTURE_GIT="$work/$case/git"
  init_git_repo "$FIXTURE_GIT"
  if [ "$have_jj" = 1 ]; then
    export FIXTURE_JJ="$work/$case/jj"
    init_jj_repo "$FIXTURE_JJ"
    export FIXTURE_JJ_PLAIN="$work/$case/jj-plain"
    init_jj_repo_plain "$FIXTURE_JJ_PLAIN"
  else
    unset FIXTURE_JJ FIXTURE_JJ_PLAIN
  fi

  if out="$(CASE="$case" VOIL_BOOTSTRAP="$bootstrap" nvim --headless -u "$root/tests/minimal_init.lua" \
    -c "luafile $root/tests/cases.lua" 2>&1)"; then
    printf 'ok   %s\n' "$case"
  else
    printf 'FAIL %s\n' "$case"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
  if [ -n "${VERBOSE:-}" ]; then
    printf '%s\n' "$out" | sed 's/^/     /'
  fi
}

run git
run failure
run config "$root/tests/bootstrap-config.lua"
run highlight
if [ "$have_jj" = 1 ]; then
  run jj
  run subdir
  run write
  run noncolocated
  run gitfirst "$root/tests/bootstrap-git-first.lua"
else
  echo "skip jj cases: jj is not installed"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
