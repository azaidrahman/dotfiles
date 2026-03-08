# zsh-config-watcher.zsh
# Detects changes to zsh config files and prompts to reload the shell.
# Checks on startup AND periodically via precmd (catches tmux pane switches).
# Source this from your .zshrc

# Cooldown in seconds between checks (avoids hashing on every prompt)
ZSH_CONFIG_WATCH_INTERVAL=${ZSH_CONFIG_WATCH_INTERVAL:-30}
# ZSH_CONFIG_WATCH_INTERVAL=${ZSH_CONFIG_WATCH_INTERVAL:-5}

__zsh_config_watcher_last_check=0
__zsh_config_watcher_prompted=0

__zsh_config_compute_checksum() {
  # Use stat mtime instead of shasum for speed (~5ms vs ~400ms)
  local mtimes=""
  if [[ -f "$HOME/.zshrc" ]]; then
    mtimes+="$(stat -f '%m' "$HOME/.zshrc" 2>/dev/null)"
  fi
  if [[ -d "$HOME/.config/zsh" ]]; then
    # Use zsh globbing instead of find for speed
    local f
    for f in "$HOME/.config/zsh/"*.zsh(N); do
      mtimes+=":$(stat -f '%m' "$f" 2>/dev/null)"
    done
  fi
  echo "$mtimes"
}

__zsh_config_watcher_check() {
  # Skip if disabled (e.g. during benchmarking)
  [[ -n "$ZSH_CONFIG_WATCH_DISABLE" ]] && return

  local now=${EPOCHSECONDS:-$(date +%s)}

  # Throttle: skip if checked recently
  if (( now - __zsh_config_watcher_last_check < ZSH_CONFIG_WATCH_INTERVAL )); then
    return
  fi
  __zsh_config_watcher_last_check=$now

  local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-config-checksums"
  local current_checksum
  current_checksum=$(__zsh_config_compute_checksum) || return

  # First run — save baseline
  if [[ ! -f "$cache_file" ]]; then
    mkdir -p "$(dirname "$cache_file")"
    echo "$current_checksum" > "$cache_file"
    return
  fi

  local saved_checksum
  saved_checksum=$(<"$cache_file")

  if [[ "$current_checksum" != "$saved_checksum" ]]; then
    # Don't prompt again if already prompted in this shell session
    if (( __zsh_config_watcher_prompted )); then
      return
    fi
    __zsh_config_watcher_prompted=1

    echo "\033[1;33m⚡ Zsh config changes detected in ~/.zshrc or ~/.config/zsh/\033[0m"
    read -q "reply?   Reload shell now? (y/n) " || true
    echo
    if [[ "$reply" == "y" ]]; then
      # Update checksum before reload so the new shell starts clean
      echo "$current_checksum" > "$cache_file"
      exec zsh
    fi
  else
    # Config matches cache — reset prompted flag (user may have reloaded another way)
    __zsh_config_watcher_prompted=0
  fi
}

# Run on initial source (new shell)
__zsh_config_watcher_check

# Register precmd hook for existing shells (tmux pane switches, etc.)
autoload -Uz add-zsh-hook
add-zsh-hook precmd __zsh_config_watcher_check
