### Added by Zinit's installer
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
unalias zi zini zpl zplg 2>/dev/null
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
autoload -Uz compinit
# Cache compinit: only full rebuild if zcompdump is older than 24h
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]] || [[ ! -f ${ZDOTDIR:-$HOME}/.zcompdump ]]; then
    compinit
else
    compinit -C  # skip security check, use cached dump
fi
# bashcompinit

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
# Annexes commented out: none of the current plugins require them
# zinit light-mode for \
#     zdharma-continuum/zinit-annex-as-monitor \
#     zdharma-continuum/zinit-annex-bin-gem-node \
#     zdharma-continuum/zinit-annex-patch-dl \
#     zdharma-continuum/zinit-annex-rust
