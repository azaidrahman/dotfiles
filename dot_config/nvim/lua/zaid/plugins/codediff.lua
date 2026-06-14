-- VSCode-style, C-backed diff viewer. Used by the standalone diff-review popup
-- (~/.tmux/scripts/claude-diff-review-init.lua); diffview stays as neogit's
-- engine. Lazy-loaded on the :CodeDiff command; the prebuilt binary
-- auto-downloads on first use.
return {
  "esmuellert/codediff.nvim",
  cmd = "CodeDiff",
}
