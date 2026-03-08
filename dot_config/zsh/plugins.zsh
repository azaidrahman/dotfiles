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
#
# zinit ice wait"2" as"command" from"gh-r" lucid \
#   mv"zoxide*/zoxide -> zoxide" \
#   atclone"./zoxide init zsh > init.zsh" \
#   atpull"%atclone" src"init.zsh" nocompile'!'
# zinit light ajeetdsouza/zoxide

# enable help in zsh
# unalias run-help 2>/dev/null
# autoload -Uz run-help
