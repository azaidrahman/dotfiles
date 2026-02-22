---
name: sensitive-env-files
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.env($|\.)
---

**Editing a .env file!**

These files often contain secrets (API keys, passwords, tokens). Before proceeding:

- Ensure this file is listed in `.gitignore`
- Never hardcode real credentials — use placeholders or secret manager references
- Double-check you're not accidentally committing secrets
