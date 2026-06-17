---
description: Copy my previous response verbatim to the macOS clipboard (for nvim MarkdownPreview via tmux prefix+p)
allowed-tools: Bash(pbcopy)
---

Take your most recent assistant response in this conversation and copy its full
raw markdown to the macOS clipboard, verbatim.

- Pipe the exact text into `pbcopy` using a heredoc, e.g.
  `pbcopy <<'CLAUDE_COPY_EOF'` … `CLAUDE_COPY_EOF`.
- Do NOT add commentary, headers, or a summary — copy the content only.
- Do NOT re-run any tools or recompute anything; just reproduce the text you
  already wrote.
- After copying, reply with a single short line confirming it's on the
  clipboard (e.g. "Copied — hit tmux prefix+p to preview").
