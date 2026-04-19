# Turbo-loaded plugins (deferred via wait ice)
zinit ice wait lucid
zinit light zsh-users/zsh-syntax-highlighting
zinit ice wait lucid
zinit light zsh-users/zsh-autosuggestions
zinit ice wait lucid
zinit light zsh-users/zsh-completions
zinit ice wait lucid
zinit light Aloxaf/fzf-tab
zinit light jeffreytse/zsh-vi-mode
# NVM is disabled (see exports.zsh), no need for lazy-load wrapper
# zinit light undg/zsh-nvm-lazy-load

# Add in plugins
# zinit snippet OMZP::sudo
# added this lib thing for git_current_branch and other functions
zinit snippet OMZ::lib/git.zsh
zinit snippet OMZP::command-not-found
zinit snippet OMZP::git

source <(fzf --zsh)
# eval "$(zoxide init --cmd cd zsh)"
eval "$(zoxide init zsh)"

# Google cloud completion (hardcoded brew prefix to avoid slow brew --prefix call)
source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"

# Kubectl completion — cached to avoid slow `kubectl completion zsh` on every shell start.
# Regenerate with: rm ~/.cache/kubectl-completion.zsh
if command -v kubectl >/dev/null 2>&1; then
  _kubectl_cache="${XDG_CACHE_HOME:-$HOME/.cache}/kubectl-completion.zsh"
  if [[ ! -f "$_kubectl_cache" ]] || [[ "$(command -v kubectl)" -nt "$_kubectl_cache" ]]; then
    mkdir -p "${_kubectl_cache:h}"
    kubectl completion zsh > "$_kubectl_cache"
  fi
  source "$_kubectl_cache"
  unset _kubectl_cache
fi
#
# zinit ice wait"2" as"command" from"gh-r" lucid \
#   mv"zoxide*/zoxide -> zoxide" \
#   atclone"./zoxide init zsh > init.zsh" \
#   atpull"%atclone" src"init.zsh" nocompile'!'
# zinit light ajeetdsouza/zoxide

# enable help in zsh
# unalias run-help 2>/dev/null
# autoload -Uz run-help
