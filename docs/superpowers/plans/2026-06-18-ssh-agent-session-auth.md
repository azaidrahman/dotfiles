# Per-login SSH agent (session auth) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-operation 1Password SSH-agent prompts with a per-login OpenSSH `ssh-agent`, seeded once from 1Password via Touch ID and silent for 12h, while inbound SSH (phone/peer-Mac) rides the forwarded agent.

**Architecture:** A launchd-managed `ssh-agent` runs at a fixed socket for the GUI login session (torn down at logout → keys wiped). `.zshenv` points `SSH_AUTH_SOCK` at that socket only when not in an incoming SSH session, and exports `GIT_SSH_COMMAND` to a wrapper that lazily seeds the agent. A hostname-aware seed helper reads the needed keys from 1Password (`op read`, one Touch ID) and `ssh-add -t 43200`s them.

**Tech Stack:** macOS launchd (`launchctl bootstrap`), OpenSSH `ssh-agent`/`ssh-add`, 1Password CLI `op` 2.34, chezmoi (age encryption + Go templates), zsh.

## Global Constraints

- This machine is `aqua` (`scutil --get LocalHostName` → `aqua`; chezmoi hostname `aqua`). The peer is `onyx`. Hostname-specific behavior must be derived at runtime, not hardcoded to one host.
- Fixed agent socket path: `$HOME/.cache/ssh/agent.sock`. Key ttl: `43200` seconds (12h).
- Seed list is per-host (keys whose pubkeys authorize outbound auth):
  - `aqua` → `op://Gamuda/Signing.BB.GD/private key` + `op://Personal Development/Auth.onyx/private key`
  - `onyx` → `op://Gamuda/Signing.BB.GD/private key` + `op://Personal Development/Auth.aqua/private key`
- `op read` MUST use the desktop biometric — do NOT set `OP_SERVICE_ACCOUNT_TOKEN` anywhere in these scripts (it would bypass the Touch ID gate). It is confirmed unset globally.
- Seeding is a no-op when `$SSH_CONNECTION` is set (inbound SSH uses the forwarded agent) — the symmetric rule for phone and peer-Mac.
- Every zsh source file in this repo is age-encrypted: read raw with `chezmoi decrypt <src>`, render with `chezmoi cat <target>`, re-encrypt plaintext stdin with `chezmoi encrypt < plain > <encrypted_...age>`. `.zshenv` is the one plaintext source (`dot_zshenv`); `.zshrc` is `encrypted_dot_zshrc.age` (not a template).
- No unit-test framework. Each task's "test" is a verification command. Steps needing biometric are marked **(USER: Touch ID)** — the executing agent cannot satisfy them; surface them to the user.
- Work from repo root `~/.local/share/chezmoi`. Only `chezmoi apply` explicitly-named files; never bare `chezmoi apply` or `--force` (the repo has unrelated pending target diffs). Commit after each task.

---

### Task 1: launchd LaunchAgent for the session ssh-agent

**Files:**
- Create: `private_Library/LaunchAgents/com.zaid.ssh-agent.plist`

**Interfaces:**
- Produces: a running `ssh-agent` reachable at `~/.cache/ssh/agent.sock` for the GUI login session. Tasks 2–4 rely on this socket path.

- [ ] **Step 1: Write the plist source**

Create `private_Library/LaunchAgents/com.zaid.ssh-agent.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.zaid.ssh-agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>mkdir -p "$HOME/.cache/ssh" &amp;&amp; rm -f "$HOME/.cache/ssh/agent.sock" &amp;&amp; exec /usr/bin/ssh-agent -D -a "$HOME/.cache/ssh/agent.sock"</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
```

(`-D` keeps ssh-agent in the foreground so launchd `KeepAlive` supervises it; the stale-socket `rm` prevents bind failures on restart.)

- [ ] **Step 2: Apply the file to ~/Library**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi apply ~/Library/LaunchAgents/com.zaid.ssh-agent.plist
ls -l ~/Library/LaunchAgents/com.zaid.ssh-agent.plist
```
Expected: file exists at the target path.

- [ ] **Step 3: Bootstrap (load) the agent into the GUI domain**

Run:
```bash
launchctl bootout gui/$(id -u)/com.zaid.ssh-agent 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.zaid.ssh-agent.plist
launchctl print gui/$(id -u)/com.zaid.ssh-agent | grep -E 'state|pid' | head
```
Expected: service present, `state = running` with a pid.

- [ ] **Step 4: Verify the socket is live and the agent is empty**

Run:
```bash
test -S ~/.cache/ssh/agent.sock && echo "SOCKET OK"
SSH_AUTH_SOCK=~/.cache/ssh/agent.sock ssh-add -l; echo "exit=$?"
```
Expected: `SOCKET OK`; `ssh-add -l` prints `The agent has no identities.` with `exit=1` (agent reachable but unseeded). NOT `exit=2` / "Could not open a connection".

- [ ] **Step 5: Commit**

```bash
git add private_Library/LaunchAgents/com.zaid.ssh-agent.plist
git commit -m "feat(ssh): launchd ssh-agent for per-login session auth"
```

---

### Task 2: `ssh-agent-seed` helper

**Files:**
- Create: `dot_local/bin/executable_ssh-agent-seed`

**Interfaces:**
- Consumes: the agent socket from Task 1 (via `$SSH_AUTH_SOCK`).
- Produces: executable `~/.local/bin/ssh-agent-seed` — idempotent; seeds this host's keys with one Touch ID; no-op when inbound (`$SSH_CONNECTION`) or already seeded. Tasks 3–4 invoke it.

- [ ] **Step 1: Write the helper**

Create `dot_local/bin/executable_ssh-agent-seed`:

```sh
#!/bin/sh
# ssh-agent-seed — load this machine's SSH keys into the per-login session
# ssh-agent from 1Password, once, with a 12h ttl. Idempotent and quiet.
#
#   - Inbound SSH ($SSH_CONNECTION set): no-op — use the forwarded agent.
#   - Agent already holds identities: no-op.
#   - Otherwise: op read each key (ONE Touch ID, batched) | ssh-add -t 43200.
#
# OP_SERVICE_ACCOUNT_TOKEN must NOT be set here, or op would skip biometric.

[ -n "$SSH_CONNECTION" ] && exit 0          # inbound: ride the forwarded agent
[ -z "$SSH_AUTH_SOCK" ] && exit 0           # no agent configured

# Reachability + already-seeded check. ssh-add -l: exit 0 = has keys,
# 1 = reachable but empty, 2 = cannot connect.
ssh-add -l >/dev/null 2>&1
case $? in
  0) exit 0 ;;                              # already seeded
  2) [ -e /dev/tty ] && echo "ssh-agent-seed: agent unreachable at $SSH_AUTH_SOCK" >/dev/tty
     exit 1 ;;
esac

host=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
case "$host" in
  aqua) keys="op://Gamuda/Signing.BB.GD/private key
op://Personal Development/Auth.onyx/private key" ;;
  onyx) keys="op://Gamuda/Signing.BB.GD/private key
op://Personal Development/Auth.aqua/private key" ;;
  *)    keys="op://Gamuda/Signing.BB.GD/private key" ;;
esac

[ -e /dev/tty ] && printf 'ssh-agent-seed: loading SSH keys from 1Password (approve once)…\n' >/dev/tty

rc=0
# Read each private key in openssh format and add with a 12h lifetime.
# IFS=newline so vault/item names with spaces survive.
OLDIFS=$IFS
IFS='
'
for ref in $keys; do
  if ! op read "${ref}?ssh-format=openssh" 2>/dev/null | ssh-add -t 43200 - >/dev/null 2>&1; then
    [ -e /dev/tty ] && echo "ssh-agent-seed: failed to load ${ref}" >/dev/tty
    rc=1
  fi
done
IFS=$OLDIFS
exit $rc
```

- [ ] **Step 2: Apply and confirm it is executable**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi apply ~/.local/bin/ssh-agent-seed
test -x ~/.local/bin/ssh-agent-seed && echo "EXECUTABLE OK"
```
Expected: `EXECUTABLE OK`.

- [ ] **Step 3: Verify the no-op paths (no biometric)**

Run:
```bash
# Inbound-SSH no-op:
SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" ~/.local/bin/ssh-agent-seed; echo "inbound exit=$?"
# Already-seeded no-op (simulate by pointing at an agent that reports keys is
# hard without keys; instead confirm it does NOT prompt when agent has a key):
echo "shellcheck:"; shellcheck ~/.local/bin/ssh-agent-seed 2>/dev/null || echo "(shellcheck not installed — skip)"
```
Expected: `inbound exit=0` (returned immediately, no Touch ID). shellcheck clean or skipped.

- [ ] **Step 4: Verify the real seed — ONE Touch ID (USER: Touch ID)**

Ask the user to run (this triggers the biometric prompt; the executing agent cannot):
```bash
SSH_AUTH_SOCK=~/.cache/ssh/agent.sock ~/.local/bin/ssh-agent-seed; echo "seed exit=$?"
SSH_AUTH_SOCK=~/.cache/ssh/agent.sock ssh-add -l
# Re-run: must be a silent no-op (already seeded):
SSH_AUTH_SOCK=~/.cache/ssh/agent.sock ~/.local/bin/ssh-agent-seed; echo "reseed exit=$?"
```
Expected: first run shows ONE 1Password prompt then `seed exit=0`; `ssh-add -l` lists 2 keys (256-bit ED25519 entries); the re-run prints nothing and `reseed exit=0`.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_ssh-agent-seed
git commit -m "feat(ssh): ssh-agent-seed — load keys from 1Password once per session"
```

---

### Task 3: `git-ssh` wrapper + interactive `ssh()` seeding

**Files:**
- Create: `dot_local/bin/executable_git-ssh`
- Modify: `encrypted_dot_zshrc.age` (decrypt → edit → re-encrypt)

**Interfaces:**
- Consumes: `~/.local/bin/ssh-agent-seed` (Task 2).
- Produces: `~/.local/bin/git-ssh` (used as `GIT_SSH_COMMAND` in Task 4); the `ssh()` shell function seeds before connecting.

- [ ] **Step 1: Write the git-ssh wrapper**

Create `dot_local/bin/executable_git-ssh`:

```sh
#!/bin/sh
# git-ssh — ssh wrapper for git (GIT_SSH_COMMAND). Seed the per-login agent on
# first git-over-SSH, then hand off to ssh. Seeding is a no-op when already
# seeded or when riding a forwarded agent.
"$HOME/.local/bin/ssh-agent-seed"
exec ssh "$@"
```

- [ ] **Step 2: Apply and confirm executable**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi apply ~/.local/bin/git-ssh
test -x ~/.local/bin/git-ssh && echo "EXECUTABLE OK"
```
Expected: `EXECUTABLE OK`.

- [ ] **Step 3: Edit the interactive `ssh()` function to seed first**

Run `chezmoi decrypt encrypted_dot_zshrc.age > /tmp/zshrc.edit`, then in `/tmp/zshrc.edit` find the `ssh()` function (starts at the `ssh() {` line) and insert the seed call as the FIRST line inside the function body. Before:

```zsh
ssh() {
    if [ -n "$TMUX" ]; then
        tmux select-pane -P 'bg=#200000'
```

After:

```zsh
ssh() {
    "$HOME/.local/bin/ssh-agent-seed"
    if [ -n "$TMUX" ]; then
        tmux select-pane -P 'bg=#200000'
```

Leave the rest of the function (and file) untouched.

- [ ] **Step 4: Re-encrypt and verify**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi encrypt < /tmp/zshrc.edit > encrypted_dot_zshrc.age
rm -f /tmp/zshrc.edit
chezmoi cat ~/.zshrc | grep -n -A2 'ssh() {'
```
Expected: the rendered `ssh()` body's first line is `"$HOME/.local/bin/ssh-agent-seed"`.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_git-ssh encrypted_dot_zshrc.age
git commit -m "feat(ssh): git-ssh wrapper + seed agent in interactive ssh()"
```

---

### Task 4: Point `.zshenv` at the session agent + wire `GIT_SSH_COMMAND`

**Files:**
- Modify: `dot_zshenv`

**Interfaces:**
- Consumes: agent socket (Task 1), `git-ssh` (Task 3).
- Produces: outbound local shells use `~/.cache/ssh/agent.sock`; git-over-SSH uses the seeding wrapper. Inbound SSH still inherits the forwarded socket (guard unchanged).

- [ ] **Step 1: Edit the SSH agent block in `dot_zshenv`**

In `dot_zshenv`, replace the existing 1Password SSH-agent block:

```zsh
# --- 1Password SSH agent (git commit signing / ssh auth from any shell) ---
# Only set when NOT inside an incoming SSH session, else we'd stomp the
# forwarded agent socket sshd provides (breaks aqua<->onyx agent forwarding).
if [ -z "$SSH_CONNECTION" ]; then
    export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
fi
```

with:

```zsh
# --- Session ssh-agent (per-login, launchd-managed; see com.zaid.ssh-agent) --
# Outbound local SSH uses our own ssh-agent, seeded once per login from
# 1Password via Touch ID (ssh-agent-seed) and silent for 12h. Only set when
# NOT inside an incoming SSH session, so a forwarded agent (phone/peer-Mac)
# always wins and the receiving end never seeds.
if [ -z "$SSH_CONNECTION" ]; then
    export SSH_AUTH_SOCK="$HOME/.cache/ssh/agent.sock"
fi

# git-over-SSH seeds the session agent on first use, then hands off to ssh.
export GIT_SSH_COMMAND="$HOME/.local/bin/git-ssh"
```

- [ ] **Step 2: Apply**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi apply ~/.zshenv
```
Expected: clean apply (only `~/.zshenv`).

- [ ] **Step 3: Verify the socket target and forwarding guard**

Run:
```bash
zsh -c 'echo $SSH_AUTH_SOCK; echo $GIT_SSH_COMMAND'
SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" zsh -c 'echo $SSH_AUTH_SOCK'
```
Expected: first → `/Users/zaid/.cache/ssh/agent.sock` and `/Users/zaid/.local/bin/git-ssh`. Second (simulated inbound) → an EMPTY line (zsh did not set it to our socket; in a real inbound session sshd would have set the forwarded socket).

- [ ] **Step 4: Commit**

```bash
git add dot_zshenv
git commit -m "feat(ssh): zshenv uses session agent + GIT_SSH_COMMAND seeding"
```

---

### Task 5: sshd agent-forwarding check + end-to-end verification + sync

**Files:** none (verification + chezmoi-sync)

- [ ] **Step 1: Confirm sshd allows agent forwarding on aqua (USER: sudo)**

Ask the user to run:
```bash
sudo sshd -T | grep -i allowagentforwarding
```
Expected: `allowagentforwarding yes` (the default). If `no`, add `AllowAgentForwarding yes` to `/etc/ssh/sshd_config.d/` and reload — note it for the user; it is a system file, not chezmoi-managed.

(Reminder for the user: the peer `onyx` needs the same, and the phone path needs the key stored in Termius with agent forwarding enabled and registered on Bitbucket — out of scope for this repo.)

- [ ] **Step 2: Fresh-login simulation — agent empty, first git push seeds once (USER: Touch ID)**

Ask the user, in a NEW terminal (so it reads the new `.zshenv`):
```bash
echo $SSH_AUTH_SOCK                       # → ~/.cache/ssh/agent.sock
ssh-add -l                                 # may already have keys from Task 2; if so:
ssh-add -D                                 # clear, to simulate fresh login
cd ~/projects/gamuda/iris                  # an SSH-remote gamuda repo
git fetch                                   # FIRST git-over-SSH
```
Expected: exactly ONE 1Password prompt during `git fetch`, then it completes. `ssh-add -l` afterward lists the keys.

- [ ] **Step 3: Second operation is silent**

Ask the user:
```bash
cd ~/projects/gamuda/iris && git fetch
```
Expected: completes with NO prompt.

- [ ] **Step 4: Shared across panes**

Ask the user to open a new tmux pane/window and run:
```bash
echo $SSH_AUTH_SOCK                        # same socket
cd ~/projects/gamuda/gt-odin && git fetch  # different SSH repo
```
Expected: same socket path; `git fetch` silent (shared agent already seeded).

- [ ] **Step 5: Peer-Mac forwarding (USER, optional if onyx reachable)**

Ask the user, from aqua:
```bash
ssh onyx 'echo $SSH_AUTH_SOCK; cd ~/projects/gamuda/iris 2>/dev/null && git fetch && echo PUSH_OK'
```
Expected: on onyx `$SSH_AUTH_SOCK` is a forwarded socket (NOT `~/.cache/ssh/agent.sock`), and `git fetch` is silent (rides aqua's forwarded agent). Skip if onyx not set up yet.

- [ ] **Step 6: `git ship` regression (USER)**

Ask the user to confirm a normal flow still works on an SSH repo (dry where possible):
```bash
cd ~/projects/gamuda/iris && git fetch origin && echo SHIP_PRELIM_OK
```
Expected: no prompt, `SHIP_PRELIM_OK`. (Full `git ship` only if they have a branch to ship.)

- [ ] **Step 7: Sync**

Invoke the `chezmoi-sync` skill to validate and push all commits from this plan.

---

## Self-Review

**Spec coverage:** launchd agent → Task 1; lazy seed helper (hostname keys, 12h ttl, op biometric, inbound no-op) → Task 2; git wiring + interactive ssh seeding → Task 3; `SSH_AUTH_SOCK` retarget + `GIT_SSH_COMMAND` (keeping `$SSH_CONNECTION` guard) → Task 4; sshd forwarding + symmetric forwarded-agent behavior + end-to-end verification + sync → Task 5. The spec's "wipe at logout" is provided by launchd's GUI-domain teardown (Task 1) plus the 12h ttl backstop (Task 2). Prereqs (Termius/Bitbucket) are called out as out-of-scope in Task 5 Step 1.

**Placeholder scan:** none. Biometric/sudo steps are explicitly marked **(USER: …)** because the executing agent cannot perform them — these are deliberate handoffs, not gaps.

**Type/name consistency:** socket path `~/.cache/ssh/agent.sock`, ttl `43200`, helper path `~/.local/bin/ssh-agent-seed`, wrapper `~/.local/bin/git-ssh`, plist label `com.zaid.ssh-agent`, and the per-host `op://…/private key` refs are identical across Tasks 1–5 and the Global Constraints.
