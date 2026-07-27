# Starship prompt — init script cached to skip the ~20ms `starship init zsh`
# subprocess; rebuilt when the starship binary is newer than the cache.
# Regenerate by hand: rm ~/.cache/starship-init.zsh
_starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship-init.zsh"
if [[ ! -f "$_starship_cache" ]] || [[ "${commands[starship]:A}" -nt "$_starship_cache" ]]; then
    mkdir -p "${_starship_cache:h}"
    starship init zsh > "$_starship_cache"
fi
source "$_starship_cache"
unset _starship_cache
