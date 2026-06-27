---
name: ctx
description: Use when the user wants to save an artifact (HTML, note, data) to their active work context, check what's in their context, look at their research files, switch context to a different ticket or topic, or reference "my ctx" / "my context" / "my research". Also use proactively when generating a persistent HTML artifact the user might want to refer back to.
---

# ctx — Active Work Context

The user has a context system that associates a named directory with whatever
they are currently working on (a ticket, a project, or any topic). Files placed
there persist across sessions and are accessible on both aqua and onyx.

## Storage layout

```
~/.config/active-ctx        # plain text: current context name (e.g. "GTI-197")
~/ctx/<name>/               # the context directory — any files live here
$CTX_DIR                    # env var → ~/ctx/<name>/ (set at shell startup)
```

## Reading the active context

Always start by reading the pointer file:

```bash
cat ~/.config/active-ctx 2>/dev/null || echo "(none)"
```

The context directory is then `~/ctx/<name>/`. If no active context exists,
ask the user what to name it before doing anything else.

## Operations

### Show active context + contents

```bash
name=$(cat ~/.config/active-ctx 2>/dev/null)
echo "context: $name"
ls -lh ~/ctx/"$name"/ 2>/dev/null || echo "(empty)"
```

### Save a file to the active context

Write to `~/ctx/<name>/<filename>` using the Write tool. Use descriptive,
kebab-case filenames (e.g. `gti-197-cost-analysis.html`, `notes.md`).

For HTML artifacts: write the full file there so it can be opened in a browser.
After saving, tell the user the path.

### Switch to a different context

```bash
echo "<new-name>" > ~/.config/active-ctx
mkdir -p ~/ctx/<new-name>
```

Report: `ctx: <new-name>  →  ~/ctx/<new-name>/`

### List all contexts

```bash
current=$(cat ~/.config/active-ctx 2>/dev/null)
for d in ~/ctx/*/; do
  name="${d%/}"; name="${name##*/}"
  [[ "$name" == "$current" ]] && echo "* $name" || echo "  $name"
done
```

### Read a file from the context

Use the Read tool on `~/ctx/<name>/<filename>`. List the directory first if
you don't know what files are there.

## Rules

- Never create files under `~/ctx/` without knowing the active context name
  first — always read `~/.config/active-ctx`.
- Use descriptive filenames, not `file1.html` or `untitled.md`.
- When saving an HTML artifact the user generated in this session, default to
  naming it after the topic and context (e.g. `gti-197-research.html`).
- Don't overwrite an existing file without telling the user.
- After any write, confirm the full path so the user can open it directly.
