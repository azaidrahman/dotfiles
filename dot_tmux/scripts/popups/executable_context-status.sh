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

main() {
  echo "not implemented yet"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
