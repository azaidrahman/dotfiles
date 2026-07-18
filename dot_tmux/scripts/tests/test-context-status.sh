#!/usr/bin/env bash
# Unit tests for the consolidated context-status popup.
set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../popups" && pwd)/executable_context-status.sh"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

# Sourcing the script must NOT run the popup (no stdout, exit 0).
out=$( source "$SCRIPT" 2>/dev/null; echo "SOURCED_OK" )
check "source is side-effect free" "SOURCED_OK" "${out##*$'\n'}"

source "$SCRIPT" 2>/dev/null   # bring parsing/render functions into scope

get() { printf '%s\n' "$1" | awk -v k="$2" '$1==k{ $1=""; sub(/^ /,""); print; exit }'; }

# --- parse_gcloud_config ------------------------------------------------
INI=$'[core]\naccount = jane.doe@example.com\nproject = my-project-123\ndisable_usage_reporting = False'
blob=$(parse_gcloud_config "$INI")
check "full unmasked account extracted" "jane.doe@example.com" "$(get "$blob" ACCOUNT)"
check "project extracted"               "my-project-123"       "$(get "$blob" PROJECT)"

blob_empty=$(parse_gcloud_config "")
check "empty ini -> empty account" "" "$(get "$blob_empty" ACCOUNT)"
check "empty ini -> empty project" "" "$(get "$blob_empty" PROJECT)"

# --- parse_kube_context --------------------------------------------------
KUBECFG=$'apiVersion: v1\ncurrent-context: gke_myproj_us-central1_gtech-svc-obs-prd\nkind: Config'
check "full context extracted, no stopword stripping" \
  "gke_myproj_us-central1_gtech-svc-obs-prd" "$(parse_kube_context "$KUBECFG")"

check "empty kubeconfig -> empty context" "" "$(parse_kube_context "")"

# --- render_gcloud --------------------------------------------------------
strip() { sed $'s/\033\\[[0-9;]*m//g'; }

blob=$(parse_gcloud_config "$INI")
out=$(render_gcloud "work" "$blob" | strip)
check "render shows configuration name" "1" "$(printf '%s\n' "$out" | grep -c 'configuration.*work')"
check "render shows full unmasked account" "1" "$(printf '%s\n' "$out" | grep -c 'jane.doe@example.com')"
check "render shows project"            "1" "$(printf '%s\n' "$out" | grep -c 'my-project-123')"

out_empty=$(render_gcloud "default" "$(parse_gcloud_config "")" | strip)
check "render gcloud fallback when not configured" "1" \
  "$(printf '%s\n' "$out_empty" | grep -c 'not configured')"

# --- render_kube -----------------------------------------------------------
out=$(render_kube "gke_myproj_us-central1_gtech-svc-obs-prd" "/tmp/fake-kubeconfig" | strip)
check "render shows full context" "1" \
  "$(printf '%s\n' "$out" | grep -c 'gke_myproj_us-central1_gtech-svc-obs-prd')"
check "render shows kubeconfig path" "1" "$(printf '%s\n' "$out" | grep -c '/tmp/fake-kubeconfig')"

out_empty=$(render_kube "" "/tmp/fake-kubeconfig" | strip)
check "render kube fallback when no context" "1" \
  "$(printf '%s\n' "$out_empty" | grep -c 'no current-context')"

# --- main(): end-to-end with fixture config dirs, no real gcloud/kube ------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/gcloud/configurations"
echo -n "work" > "$TMP/gcloud/active_config"
cat > "$TMP/gcloud/configurations/config_work" <<'EOF'
[core]
account = jane.doe@example.com
project = my-project-123
EOF

cat > "$TMP/kubeconfig" <<'EOF'
apiVersion: v1
current-context: gke_myproj_us-central1_gtech-svc-obs-prd
kind: Config
EOF

out=$(printf 'x' | GCLOUD_CONFIG_DIR="$TMP/gcloud" KUBECONFIG="$TMP/kubeconfig" bash "$SCRIPT" | strip)
check "main shows gcloud account"  "1" "$(printf '%s\n' "$out" | grep -c 'jane.doe@example.com')"
check "main shows gcloud project"  "1" "$(printf '%s\n' "$out" | grep -c 'my-project-123')"
check "main shows kube context"    "1" "$(printf '%s\n' "$out" | grep -c 'gke_myproj_us-central1_gtech-svc-obs-prd')"
check "main shows close hint"      "1" "$(printf '%s\n' "$out" | grep -c '\[any key to close\]')"

# Missing config dirs -> both fallbacks, no crash
out=$(printf 'x' | GCLOUD_CONFIG_DIR="$TMP/no-such-dir" KUBECONFIG="$TMP/no-such-kubeconfig" bash "$SCRIPT" | strip)
check "main gcloud fallback when unconfigured" "1" "$(printf '%s\n' "$out" | grep -c 'not configured')"
check "main kube fallback when unconfigured"   "1" "$(printf '%s\n' "$out" | grep -c 'no current-context')"

exit $fail
