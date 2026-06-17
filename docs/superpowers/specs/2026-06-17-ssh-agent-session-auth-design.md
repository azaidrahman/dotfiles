# Per-login SSH agent (stop the constant 1Password prompts) — design

Date: 2026-06-17
Status: approved (brainstorm), pending implementation plan

## Problem

Every git push/fetch/pull over SSH (8 gamuda repos use `git@bitbucket.org:...`
remotes) and every tailnet hop (`ssh aqua`/`ssh onyx`) authenticates through the
1Password SSH agent, which prompts for biometric approval **per operation**. The
1Password agent has no "approve once for this login session" mode, so the user
is constantly interrupted.

Commit signing is NOT involved — `commit.gpgsign = false` in both the personal
and gamuda git configs. The trigger is SSH **authentication**, not signing. So
this design does not touch `op-ssh-sign` / `gpg.ssh.program`.

## Goal

One biometric approval per login session, then silent SSH for the rest of the
session. Keys are wiped when the login session ends (logout/shutdown). The phone
(Termius) and peer-Mac (aqua↔onyx) paths must keep working without prompts on
the receiving end.

## Decisions (from brainstorm)

- Use a standard OpenSSH `ssh-agent` for the session, seeded once from 1Password
  (`op read`, biometric). Accepts the tradeoff that the private keys live in
  agent memory for the session instead of being gated per-use by 1Password.
- Session = **per login**: a launchd-managed agent shared by all terminals/tmux
  panes, torn down at logout/shutdown.
- Keys also carry a **12h ttl** (`ssh-add -t`) as a second backstop.
- **Incoming SSH always uses the forwarded agent** — symmetric for phone and
  peer Mac. The receiving machine never seeds for a forwarded session.
- Seed loads ALL keys needed for outbound auth in one batch: the Bitbucket git
  key + the tailnet auth key for the peer.

## Architecture

Two authentication contexts, one principle (seed once, then silent):

### Local (this Mac, outbound)

1. **launchd LaunchAgent** runs an empty `ssh-agent` at a fixed socket
   `~/.cache/ssh/agent.sock`, started at GUI login, torn down at logout/shutdown
   (so loaded keys are wiped when the login session ends).
2. **`.zshenv`** points `SSH_AUTH_SOCK` at that socket, **only when not in an
   incoming SSH session** — reusing the existing `[[ -z "$SSH_CONNECTION" ]]`
   guard (today it points at the 1Password socket; we change the target).
3. **Lazy seed** on first git-over-SSH or first interactive `ssh` to a peer:
   if the agent holds no identities, `op read` the keys from 1Password (one
   Touch ID) and `ssh-add -t 43200` (12h) them. Every later op is silent.

### Inbound (phone via Termius, OR peer Mac aqua↔onyx)

- The client forwards its agent (`ForwardAgent yes`). On the receiving machine
  the incoming session's forwarded `SSH_AUTH_SOCK` is preserved (the
  `$SSH_CONNECTION` guard skips the override), so `git push` and onward hops use
  the forwarded keys. No key stored or seeded on the receiving end; nothing left
  behind on disconnect.
- Symmetric rule: **each Mac seeds its own agent once per login; every inbound
  SSH rides the forwarded agent and never seeds.**
- Because a forwarded agent must satisfy both the `aqua→onyx` SSH hop AND the
  far-end `git push`, the seed batch includes the tailnet auth key as well as
  the Bitbucket key.

## Components & files

| File | Kind | Responsibility |
|---|---|---|
| `private_Library/LaunchAgents/<label>.plist` | new, chezmoi | Run `ssh-agent -D -a ~/.cache/ssh/agent.sock`, `KeepAlive`, GUI-domain (login-scoped). Creates `~/.cache/ssh` if needed (via a wrapper or `RunAtLoad` script). |
| `dot_zshenv` | modify | Change the local-shell `SSH_AUTH_SOCK` target from the 1Password socket to `~/.cache/ssh/agent.sock` (keep the `$SSH_CONNECTION` guard verbatim so forwarding still wins inbound). |
| `dot_local/bin/executable_ssh-agent-seed` | new, chezmoi | Idempotent seed helper (details below). |
| `dot_local/bin/executable_git-ssh` | new, chezmoi | Tiny wrapper: run `ssh-agent-seed`, then `exec ssh "$@"`. Wired into git via `GIT_SSH_COMMAND`/`core.sshCommand`. |
| git config (`~/.gitconfig`, chezmoi-managed) | modify | Set `core.sshCommand = ~/.local/bin/git-ssh` (or export `GIT_SSH_COMMAND` in `.zshenv`) so git-over-SSH seeds transparently. |
| interactive `ssh()` function (in `.zshrc`) | modify | Call `ssh-agent-seed` before `command ssh "$@"` so tailnet `ssh aqua/onyx` also seeds (DRY: same helper). |
| sshd on aqua/onyx | verify/set | `AllowAgentForwarding yes` (default on; confirm). |

### `ssh-agent-seed` behavior

- No-op fast path: if `SSH_AUTH_SOCK` is a forwarded/inbound socket
  (`[[ -n "$SSH_CONNECTION" ]]`) → do nothing (use the forward).
- If `ssh-add -l` already lists identities → do nothing (already seeded).
- Else, for each key in this machine's seed list, pipe the private key from
  1Password into ssh-add with a 12h ttl:
  `op read "op://<vault>/<item>/private key?ssh-format=openssh" | ssh-add -t 43200 -`
  This is the single Touch ID moment (batched across keys).
- Seed list is hostname-specific (`scutil --get LocalHostName`):
  - **aqua** → Bitbucket git key (`Signing.BB.GD`, Gamuda) + `Auth.onyx`
    (Personal Development).
  - **onyx** → Bitbucket git key (`Signing.BB.GD`, Gamuda) + `Auth.aqua`
    (Personal Development).
  (Exact item/vault names and the `private key` field reference are verified in
  the plan against `op item get`; `Signing.GH.HOME` is omitted — GitHub is HTTPS,
  not SSH.)
- `OP_SERVICE_ACCOUNT_TOKEN` must remain unset in the seed helper's environment
  so `op read` uses the desktop app biometric (it is only ever set inside
  `git-credential-op`, never exported globally — confirmed).

## Lifecycle & cleanup

- **Seed:** lazy, one Touch ID, loads all keys `-t 43200` (12h).
- **Session:** agent shared by every pane/window; all SSH ops silent.
- **Wipe:** launchd tears the agent down at logout/shutdown → keys gone. The 12h
  ttl is a backstop (mid-session expiry → one re-prompt on next use).

## Out of scope / prerequisites

- **Manual (not dotfiles):** store the SSH key in Termius on the phone and enable
  its agent forwarding; confirm the key is registered on the Bitbucket account.
- **Verified in the plan:** `op read` can export each private key in openssh
  format (load-bearing); `AllowAgentForwarding yes` on aqua/onyx; the
  `GIT_SSH_COMMAND`/`core.sshCommand` wiring does not break the `git ship` alias
  or worktree flows.
- 1Password's `agent.toml` stays as the key *source* (read via `op`); we simply
  stop using its socket as `SSH_AUTH_SOCK` for outbound local SSH. The 1Password
  agent may keep running; nothing else depends on it after this change.

## Verification

- After login + first `git push` on a gamuda SSH repo: exactly one Touch ID,
  then `ssh-add -l` shows the seeded keys; a second push prompts nothing.
- `echo $SSH_AUTH_SOCK` in a normal terminal → `~/.cache/ssh/agent.sock`.
- Open a new tmux pane → same socket, no new prompt (shared agent).
- `ssh onyx` from aqua → no prompt after seed; on onyx `echo $SSH_AUTH_SOCK`
  shows a forwarded socket (not `~/.cache/ssh/agent.sock`), and `git push` there
  is silent (forwarded agent).
- Termius → aqua: `git push` silent via forwarded agent; `ssh-add -l` on aqua in
  that session reflects the forwarded keys.
- Logout/login (or reboot): agent empty again → next push prompts once.
- `git ship develop` on a gamuda repo still works end-to-end.
