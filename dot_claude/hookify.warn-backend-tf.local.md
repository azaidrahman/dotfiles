---
name: warn-backend-tf
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: backend\.tf$
  - field: new_text
    operator: regex_match
    pattern: backend\s+"
---

Editing a `backend` block — state migration required (`terraform init -migrate-state`). Confirm bucket/prefix.
