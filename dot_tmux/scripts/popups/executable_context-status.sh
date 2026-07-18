#!/usr/bin/env bash
# prefix+I : consolidated context-status popup — gcloud account/project,
# kube current-context. Always shows current state regardless of the
# triggering pane's cwd (no work-projects-dir gate — this is on-demand).
#
# Adding a future section (AWS profile, docker context, ...): write a
# parse_* function (pure, takes raw text, prints KEY value lines) and a
# render_* function, then call both from main().

set -u

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'

# parse_gcloud_config <ini_text> : extract account + project from a gcloud
# config ini blob. Empty fields when absent.
parse_gcloud_config() {
  local text=$1 account project
  account=$(printf '%s\n' "$text" | awk -F'= ' '/^account = /{print $2; exit}')
  project=$(printf '%s\n' "$text" | awk -F'= ' '/^project = /{print $2; exit}')
  printf 'ACCOUNT %s\nPROJECT %s\n' "$account" "$project"
}

# parse_kube_context <kubeconfig_text> : extract the full current-context
# (no shortening/stopword stripping — the popup has room for the whole name).
parse_kube_context() {
  local text=$1
  printf '%s\n' "$text" | awk -F': ' '/^current-context:/{print $2; exit}'
}

# render_gcloud <config_name> <parse_gcloud_config output> : gcloud section.
render_gcloud() {
  local config_name=$1 blob=$2 account project
  account=$(printf '%s\n' "$blob" | awk '$1=="ACCOUNT"{ $1=""; sub(/^ /,""); print; exit }')
  project=$(printf '%s\n' "$blob" | awk '$1=="PROJECT"{ $1=""; sub(/^ /,""); print; exit }')
  printf '  %sgcloud%s\n' "$c_bold" "$c_reset"
  if [ -z "$account" ]; then
    printf '  %snot configured%s\n' "$c_dim" "$c_reset"
  else
    printf '  configuration  %s\n' "$config_name"
    printf '  account        %s\n' "$account"
    printf '  project        %s\n' "${project:-<none>}"
  fi
  echo
}

# render_kube <context> <kubeconfig_path> : kube section.
render_kube() {
  local context=$1 path=$2
  printf '  %skube%s\n' "$c_bold" "$c_reset"
  if [ -z "$context" ]; then
    printf '  %sno current-context%s\n' "$c_dim" "$c_reset"
  else
    printf '  context   %s\n' "$context"
    printf '  path      %s\n' "$path"
  fi
  echo
}

main() {
  clear 2>/dev/null
  echo
  printf '  %sContext status%s\n\n' "$c_bold" "$c_reset"

  local gconf_dir="${GCLOUD_CONFIG_DIR:-$HOME/.config/gcloud}"
  local active; active=$(cat "$gconf_dir/active_config" 2>/dev/null); active=${active:-default}
  local gtext; gtext=$(cat "$gconf_dir/configurations/config_${active}" 2>/dev/null)
  render_gcloud "$active" "$(parse_gcloud_config "$gtext")"

  local kpath="${KUBECONFIG:-$HOME/.kube/config}"
  local ktext; ktext=$(cat "$kpath" 2>/dev/null)
  render_kube "$(parse_kube_context "$ktext")" "$kpath"

  printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
  local old_stty; old_stty=$(stty -g 2>/dev/null)
  stty -echo -icanon min 1 time 0 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
