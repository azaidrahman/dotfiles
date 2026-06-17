# Key bindings
bindkey -v

# Options
setopt notify
setopt promptsubst
setopt numericglobsort

# History Config
HISTSIZE=1000
HISTFILE=~/zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
# hist_ignore_dups is redundant — hist_ignore_all_dups already covers it
# setopt hist_ignore_dups
setopt hist_find_no_dups
