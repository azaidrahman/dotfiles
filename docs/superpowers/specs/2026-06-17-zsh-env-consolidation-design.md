# Zsh env/PATH consolidation — design

Date: 2026-06-17
Status: approved (brainstorm), pending implementation plan

## Problem

Env vars, PATH edits, and secrets are scattered across `~/.zshenv`, `~/.zshrc`,
and `~/.config/zsh/exports.zsh` with overlaps and inconsistent idioms:

- `SSH_AUTH_SOCK` is set in **both** `.zshenv` and `exports.zsh` with
  near-identical `$SSH_CONNECTION` guards.
- PATH edits live in two files and use **three** different styles:
  `path_prepend`/`path_append` helper functions (defined in `.zshrc`, used in
  `exports.zsh` — load-order coupling), and raw `path=("${(@)path:#...}")` array
  surgery for the homebrew/pyenv-shims "force to front" hacks.
- `exports.zsh` mixes editor logic, tool config, project-dir shortcuts, pyenv
  init, gcloud sourcing, and inline secrets in one ~80-line file.
- Secrets are inline: `LITELLM_MASTER_KEY` (in encrypted `.zshenv`) and
  `BITBUCKET_API_TOKEN` (in encrypted `exports.zsh`). This forces both files to
  be encrypted `.age`, so they can't be plainly tracked/diffed in chezmoi.

Goal: one place that builds PATH, one place for secrets, no duplication,
uniform idioms, optimized for **speed and readability**.

## Key constraint: `path_helper`

`/etc/zprofile` runs `/usr/libexec/path_helper` on every **login** shell, which
rebuilds PATH putting system dirs (`/usr/bin`) ahead of `/opt/homebrew/bin`.
Order of execution: `.zshenv` → `/etc/zprofile` (path_helper) → `.zshrc`.

Consequence: PATH cannot live entirely in `.zshenv`. Non-login / non-interactive
shells (e.g. Claude Code's Bash tool, scripts, cron) read only `.zshenv` and get
the correct order. Login interactive shells get reshuffled by path_helper and
need a cheap re-assert in `.zshrc` afterward. This is why today's homebrew /
pyenv-shims surgery lives at the bottom of `.zshrc`.

## Decisions (from brainstorm)

- PATH + core/PATH-dependent env live in `.zshenv`, plaintext + chezmoi-tracked.
- All other non-sensitive env lives in `exports.zsh` (interactive, plaintext).
- Secrets move to a single new encrypted file sourced early from `.zshenv`.
- One PATH idiom everywhere: declarative `typeset -U path` (no helper functions,
  no array-filter surgery). Fastest and most readable.

## File responsibilities (target layering)

| File | Tracked | Sourced by | Holds |
|---|---|---|---|
| `.zshenv` | plaintext, chezmoi | all shells | source secrets → SSH agent guard → PATH-dep vars (`PYENV_ROOT`, `BUN_INSTALL`, `GOPATH`, `XDG_CONFIG_HOME`) → one declarative `typeset -U path` block → gcloud `path.zsh.inc` |
| `encrypted_secrets.zsh.tmpl.age` *(new)* | encrypted | from `.zshenv`, early | `LITELLM_MASTER_KEY`, `BITBUCKET_EMAIL`, `BITBUCKET_API_TOKEN` |
| `.zshrc` | (unchanged file) | interactive | profiling, quickterminal/mobile guards, source order, fpath/autoload, `ssh()` func, 3-line PATH priority re-assert after path_helper |
| `exports.zsh` | plaintext (was encrypted) | interactive (from `.zshrc`) | all remaining non-sensitive, non-PATH env, grouped into labeled sections |
| `launch.zsh`, `plugins.zsh`, `completions.zsh`, `general.zsh`, `theme.zsh` | unchanged | — | already well-scoped; not touched |

## `.zshenv` PATH block

Replaces all scattered PATH edits and deletes the `path_prepend`/`path_append`
helpers:

```zsh
typeset -U path                      # auto-dedupe, keeps first occurrence
path=(
  $PYENV_ROOT/shims                  # pythons for scripts too
  /opt/homebrew/bin
  $HOME/.local/bin
  $HOME/.bun/bin
  $HOME/go/bin
  /opt/homebrew/opt/openjdk/bin
  /opt/homebrew/opt/postgresql@18/bin
  $path                              # inherited
  /Applications/Obsidian.app/Contents/MacOS
  $HOME/.iximiuz/labctl/bin
)
```

PATH-dependency vars set before the block: `XDG_CONFIG_HOME`, `PYENV_ROOT`,
`BUN_INSTALL`, and a `GOPATH` default if relied upon (else `$HOME/go/bin` is
hardcoded as today). gcloud `path.zsh.inc` is sourced after the block (it is
PATH-affecting); its completion stays in `plugins.zsh`.

SSH agent guard appears once in `.zshenv` (the duplicate in `exports.zsh` is
removed):

```zsh
if [[ -z "$SSH_CONNECTION" ]]; then
    export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
fi
```

## `.zshrc` PATH re-assert

After path_helper has run (i.e. in `.zshrc`), a cheap re-assert; dedupe does the
work, no subshells:

```zsh
# path_helper (/etc/zprofile) reshuffles system dirs to the front on login
# shells; force our priority interpreters back ahead of it.
path=($PYENV_ROOT/shims /opt/homebrew/bin $path)
```

The bottom-of-`.zshrc` PATH surgery (bun prepend, homebrew filter+prepend, pyenv
shims filter+prepend, labctl append) is removed — those dirs now live in the
zshenv block. `BUN_INSTALL` moves to zshenv. The two `path_prepend`/`path_append`
function definitions are deleted (no remaining callers).

## `exports.zsh` sectioning + pruning

Reorganized into labeled sections; dead commented-out code pruned (`NVM`,
`ZUNO`, `BROWSER`, `npm-global`, the duplicate gcloud-completion comment):

```
# === Editor ===        VISUAL/EDITOR (nvr-aware), SUDO_EDITOR, FCEDITOR
# === Prompt & UI ===   STARSHIP_CONFIG, TERMINAL
# === Tools ===         FZF_DEFAULT_COMMAND, GOKU_EDN_CONFIG_FILE
# === Pyenv init ===    interactive init cache (shims path already in zshenv)
# === Git over SSH ===  GIT_CONFIG_* signing override
# === Project dirs ===  GCP_SCRIPTS, WTREE, INFRA, GTECH_DOCS, VAULT_PATH
```

All PATH-affecting lines (`go/bin`, `openjdk`, `obsidian`, `postgresql`,
`.local/bin`, `pyenv bin`, gcloud `path.zsh.inc`) move out of `exports.zsh` into
zshenv. `EDITOR`/`VISUAL` stay interactive-only in `exports.zsh` — matches
today's behavior, no regression.

## Secrets file

New `dot_config/zsh/encrypted_secrets.zsh.tmpl.age` (chezmoi template, values
pulled from 1Password at `chezmoi apply` time, encrypted at rest). Sourced
early from `.zshenv` so all shells see the secrets. Holds `LITELLM_MASTER_KEY`,
`BITBUCKET_EMAIL`, `BITBUCKET_API_TOKEN`.

After this, `encrypted_dot_zshenv.age` becomes plaintext `dot_zshenv`, and
`encrypted_exports.zsh.tmpl.age` becomes plaintext `exports.zsh`.

## Out of scope

- No changes to plugin loading, completion engine, prompt, or history config.
- No new abstractions beyond the single PATH block and secrets file.
- No unrelated refactoring of `launch/plugins/completions/general/theme`.

## Verification

- `zsh -lic 'echo $PATH'` (login interactive) — homebrew/pyenv shims ahead of
  `/usr/bin`; no duplicate entries.
- `zsh -c 'echo $PATH'` (non-interactive) — correct order from zshenv alone.
- `echo $LITELLM_MASTER_KEY $BITBUCKET_API_TOKEN` resolve in a fresh shell.
- `command -v python pyenv brew psql java` resolve to expected paths.
- Startup time not regressed (`,zsh-bench` if available).
- `chezmoi apply` renders all three files cleanly; secrets decrypt.
