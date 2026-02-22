---
name: warn-tfstate-edit
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.tfstate(\.backup)?$
---

**Do NOT manually edit Terraform state files!**

Manual edits cause:

- State corruption and drift
- Resource tracking failures
- Potential resource destruction on next apply

Use `terraform state` commands instead:
- `terraform state mv` — rename/move resources
- `terraform state rm` — remove from state
- `terraform import` — import existing resources
