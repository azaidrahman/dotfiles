---
name: warn-tfstate-edit
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.tfstate(\.backup)?$
---

Don't hand-edit `.tfstate`. Use `terraform state mv|rm` or `terraform import`.
