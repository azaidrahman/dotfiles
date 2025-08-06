# function to run yazi with the current directory as the cwd
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

function v() {
    local file="$1"
    # local path=$(zoxide query -l | xargs -I {} find {} -name "$file" -type f 2>/dev/null | head -n 1)
    local target=$(zoxide query "$file")       

    if [ -n "$target" ]; then
        nvim "$target"
    else
        echo "File not found: $target"
    fi
}
