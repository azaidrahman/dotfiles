path_prepend "/opt/homebrew/bin"
# path_prepend "$HOME/.npm-global/bin"
export XDG_CONFIG_HOME="$HOME/.config"

export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$HOME/.local/bin"
[[ -d $PYENV_ROOT/bin ]] && path_prepend "$PYENV_ROOT/bin"

# Cache pyenv init output (regenerate with: rm ~/.cache/pyenv-init.zsh)
# Strips 'command pyenv rehash' from cache to avoid blocking shell on stale locks;
# rehash runs in background instead.
_pyenv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/pyenv-init.zsh"
if [[ ! -f "$_pyenv_cache" ]] || [[ "$PYENV_ROOT/bin/pyenv" -nt "$_pyenv_cache" ]]; then
    mkdir -p "${_pyenv_cache:h}"
    pyenv init - zsh | grep -v 'command pyenv rehash' > "$_pyenv_cache"
fi
source "$_pyenv_cache"
unset _pyenv_cache
# Clean up stale lock and rehash in background (never blocks shell startup)
{ rm -f "$PYENV_ROOT/shims/.pyenv-shim"; command pyenv rehash; } &!

if [ -n "$NVIM_LISTEN_ADDRESS" ]; then
    export VISUAL="nvr -cc split --remote-wait +'set bufhidden=wipe'"
    export EDITOR="nvr -cc split --remote-wait +'set bufhidden=wipe'"
else
    export VISUAL="nvim"
    export EDITOR="nvim"
fi

# export NVM_DIR="$HOME/.nvm"
# [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
# [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi

# Duplicate gcloud completion — kept in plugins.zsh via brew --prefix instead
# if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

## COMMON VARIABLES
# EDITOR/VISUAL already set conditionally above (lines 11-17); removed duplicate unconditional exports
export SUDO_EDITOR="nvim"
export FCEDITOR="nvim"
export TERMINAL="Ghostty"
# export ZUNO="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ZUNO/"
# export BROWSER="app.zen-browser.zen"
#
export FZF_DEFAULT_COMMAND='rg --files --hidden -g !.git/'

export GCP_SCRIPTS="$HOME/projects/gamuda/gtech-platform-infra-monorepo/scripts/"

# GOLANG
path_append "$HOME/go/bin"

# 1password
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

export STARSHIP_CONFIG="$HOME/.config/zsh/starship.toml"

export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export WTREE="$HOME/projects/gamuda/worktrees"

# GOKU (KARABINER)
export GOKU_EDN_CONFIG_FILE="$HOME/.config/karabiner/karabiner.edn"

export INFRA="$HOME/projects/gamuda/gtech-platform-infra-monorepo/"
