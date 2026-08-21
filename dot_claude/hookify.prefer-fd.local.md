---
name: prefer-fd
enabled: true
event: bash
pattern: \bfind\s+.*-i?name\b
---

This command runs `find` with a name filter. Use `fd` instead. It has a simpler syntax and better defaults.
