---
name: block-force-push
enabled: true
event: bash
action: block
pattern: git\s+push\s+(.*\s)?(--force(?!-with-lease)|-f)(\s|$)
---

**Blocked: Force push detected!**

Force pushing can:

- Overwrite teammates' commits
- Break CI/CD pipelines
- Cause divergent state across branches

Use `git push --force-with-lease` if you absolutely must, or rebase locally and do a normal push.
