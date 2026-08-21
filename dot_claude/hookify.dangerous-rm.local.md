---
name: dangerous-rm
enabled: true
event: bash
action: block
pattern: rm\s+(-\S+\s+)*-\S*[rf]\S*[rf]\S*(\s|$)|rm\s+(-\S+\s+)*-\S*r\S*\s+(-\S+\s+)*-\S*f\S*(\s|$)|rm\s+(-\S+\s+)*-\S*f\S*\s+(-\S+\s+)*-\S*r\S*(\s|$)
---

**Blocked: `rm -rf` is too dangerous!**

This command can cause irreversible data loss. Instead:

- Remove specific files by name: `rm file.txt`
- Use `rm -r` (without `-f`) so you get prompted for confirmation
- Move to trash instead of deleting permanently
