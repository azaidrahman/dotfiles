# Archive: the mobile tmux profile for Termius

Retired on 2026-09-05. These files stay in the repository for reference.
Chezmoi does not deploy them, because `.chezmoiignore` excludes `archive/`.

## What these files did

The phone connected to the Mac with Termius over SSH. Termius draws a plain
terminal. It does not understand the tmux status bar of this configuration,
which uses true color and Nerd Font glyphs. The result was a large number of
formatting errors on the phone.

To work around this, `.zshrc` looked for `LC_TERMINAL=Termius`, `LC_TERMINAL=Blink`,
or `LC_MOBILE=1` on an incoming SSH session. If it found one, it started the
files below.

| File | Purpose |
|---|---|
| `executable_mobile-attach.sh` | Creates or attaches the `mobile` tmux session. |
| `visual-mobile.conf` | Applies a plain ASCII status bar to the `mobile` session. |
| `executable_mobile-link-menu.sh` | Shows a menu on `prefix+b`. The menu links a window from another session into `mobile`. |
| `executable_mobile-unlink-all.sh` | Unlinks every borrowed window when the phone detaches. |
| `starship-mobile.toml` | A prompt with no Nerd Font glyphs. |

## Why we retired them

The phone now uses rootshell, which speaks tmux control mode (`tmux -CC`).
In control mode, tmux sends structured text instead of drawing a terminal.
The application draws each tmux window as a native tab, and each pane as a
native split. Therefore tmux draws no status bar, no window tabs, and no pane
borders, and there is no chrome left to corrupt.

Control mode also replaces `prefix+b`. Every window in the session is already
a tab, so the phone does not need to borrow a window from another session.

## Known faults in this code

If you restore these files, correct these faults first.

- `starship-mobile.toml` never applied. `dot_config/zsh/exports.zsh.tmpl` sets
  `STARSHIP_CONFIG` on every shell, which overwrote the value that `.zshrc` set.
- `visual-mobile.conf` set `aggressive-resize` with a session target. This is a
  window option. Without the `-w` flag, the option applied only to the current
  window.
- `bind b` in `visual-mobile.conf` is a global binding. Key tables belong to the
  tmux server, so the binding also reached desktop clients.
- tmux-continuum saved the `mobile` session every minute. A restore returned
  borrowed windows as windows of `mobile`, so `mobile-unlink-all.sh` could not
  clean them.

## How to restore

1. Move each file back to its original location:

   ```
   git mv archive/mobile-termius/executable_mobile-attach.sh      dot_tmux/scripts/
   git mv archive/mobile-termius/executable_mobile-link-menu.sh   dot_tmux/scripts/
   git mv archive/mobile-termius/executable_mobile-unlink-all.sh  dot_tmux/scripts/
   git mv archive/mobile-termius/visual-mobile.conf               dot_tmux/conf.d/
   git mv archive/mobile-termius/starship-mobile.toml             dot_config/zsh/
   ```

2. Restore the guard in `encrypted_dot_zshrc.age`. The guard is encrypted, so
   `git log -S` cannot find it. Decrypt the version from the parent of the
   commit that created this directory:

   ```
   c=$(git log --diff-filter=A --format=%H -1 -- archive/mobile-termius/README.md)
   git show "$c^:encrypted_dot_zshrc.age" > /tmp/zshrc-old.age
   chezmoi decrypt /tmp/zshrc-old.age | sed -n '14,29p'
   ```
3. Delete the matching lines from `.chezmoiremove`.
4. Run `chezmoi apply`.
