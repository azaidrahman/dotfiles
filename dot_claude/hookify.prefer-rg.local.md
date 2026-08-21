---
name: prefer-rg
enabled: true
event: bash
pattern: (^|[;&|]\s*)grep\s+(\S+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*(\s|$)
---

This command runs a recursive `grep`. Use `rg` instead. It is faster and skips ignored files by default.
