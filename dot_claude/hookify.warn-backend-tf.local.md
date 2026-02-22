---
name: warn-backend-tf
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: backend\.tf$
---

**Editing a Terraform backend configuration!**

Changing `backend.tf` can orphan or corrupt Terraform state. Before proceeding:

- Are you sure you want to change the state backend?
- Have you backed up the current state with `terraform state pull`?
- State migrations require `terraform init -migrate-state`
- Wrong bucket/prefix = lost state = manual recovery
