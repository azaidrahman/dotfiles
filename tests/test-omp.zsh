#!/usr/bin/env zsh
# Smoke tests for the normal OMP launcher. Run with: zsh tests/test-omp.zsh
emulate -LR zsh
set -euo pipefail

repo_root=${0:A:h:h}
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export OMP_CAPTURE="$tmpdir/omp-args"
export OMP_PROXY_CAPTURE="$tmpdir/proxy-args"
mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/omp" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$OMP_CAPTURE"
SH
chmod +x "$tmpdir/bin/omp"
export PATH="$tmpdir/bin:$PATH"

function _litellm_proxy() {
  print -r -- "$1" >>"$OMP_PROXY_CAPTURE"
}

function omp() {
  source "$repo_root/dot_config/zsh/functions/omp"
}

function fail() {
  print -u2 -r -- "FAIL: $1"
  exit 1
}

function assert_line() {
  grep -Fx -- "$2" "$1" >/dev/null || fail "expected '$2' in $1"
}

function assert_no_line() {
  if grep -Fx -- "$2" "$1" >/dev/null; then
    fail "did not expect '$2' in $1"
  fi
}

function assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || fail "expected '$2' in $1"
}

function reset_captures() {
  : >"$OMP_CAPTURE"
  : >"$OMP_PROXY_CAPTURE"
}

reset_captures
omp
assert_line "$OMP_PROXY_CAPTURE" "omp"
assert_line "$OMP_CAPTURE" "--append-system-prompt"
assert_no_line "$OMP_CAPTURE" "--model"
assert_no_line "$OMP_CAPTURE" "--thinking"
assert_contains "$OMP_CAPTURE" "Use start-ticket for ticket work and start-worktree for ticketless work."

reset_captures
omp --model litellm/gemini-3.5-flash
assert_line "$OMP_PROXY_CAPTURE" "omp"
assert_line "$OMP_CAPTURE" "--model"
assert_line "$OMP_CAPTURE" "litellm/gemini-3.5-flash"

print -r -- "PASS: omp launcher behavior"
