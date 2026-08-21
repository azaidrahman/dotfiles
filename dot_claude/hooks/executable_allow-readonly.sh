#!/bin/bash
# Auto-allow read-only gcloud and terraform commands, including pipelines
# through common read-only filters (jq, grep, head, etc.).
# PreToolUse hook for Bash tool.

CMD=$(jq -r '.tool_input.command // ""')

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Disqualify anything with redirection or command/process substitution — too
# hard to reason about safely.
case "$CMD" in
  *'>'*|*'`'*|*'$('*|*'<('*) exit 0 ;;
esac

# Strip flags and quoted strings from a single segment; echo the cleaned form.
clean_segment() {
  echo "$1" | sed "s/ --[^ ]*//g; s/ -[a-zA-Z][^ ]*//g; s/\"[^\"]*\"//g; s/'[^']*'//g"
}

# Returns 0 if the segment is a recognized read-only gcloud/terraform invocation.
is_readonly_segment() {
  local seg trimmed cleaned verb sub2
  seg="$1"
  trimmed=$(echo "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  case "$trimmed" in
    gcloud\ *|gcloud)
      cleaned=$(clean_segment "$trimmed")
      verb=$(echo "$cleaned" | tr -s ' ' '\n' | grep -xE 'list|describe|get-iam-policy|get-value|read|export|info' | head -1)
      [ -n "$verb" ] && return 0
      return 1
      ;;
    terraform\ *|terraform)
      local sub
      sub=$(echo "$trimmed" | awk '{print $2}')
      case "$sub" in
        plan|show|output|validate|fmt|version|providers|graph)
          return 0 ;;
        state)
          sub2=$(echo "$trimmed" | awk '{print $3}')
          case "$sub2" in list|show|pull) return 0 ;; esac
          return 1 ;;
        workspace)
          sub2=$(echo "$trimmed" | awk '{print $3}')
          case "$sub2" in list|show) return 0 ;; esac
          return 1 ;;
      esac
      return 1
      ;;
  esac
  return 1
}

# Returns 0 if the segment is a read-only post-processing filter. These are
# allowed only when chained after a gcloud/terraform read, never as the first
# segment.
is_readonly_filter() {
  local seg trimmed tool
  seg="$1"
  trimmed=$(echo "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  tool=$(echo "$trimmed" | awk '{print $1}')

  case "$tool" in
    jq|yq|grep|rg|head|tail|wc|cat|awk|column|tr|sort|uniq|less|most)
      # sed is read-only by default but `sed -i ...` mutates files. Handle below.
      return 0 ;;
    sed)
      case " $trimmed " in
        *' -i '*|*' -i'*) return 1 ;;
      esac
      return 0 ;;
  esac
  return 1
}

# Split CMD on |, ;, &&, || into segments; iterate.
# We use awk with a regex FS to split on these operators.
SEGMENTS=$(echo "$CMD" | awk '{
  n = split($0, parts, /\|\||&&|[|;]/)
  for (i=1; i<=n; i++) print parts[i]
}')

FIRST=1
FAIL=0
while IFS= read -r SEG; do
  # Skip empty segments produced by splitting.
  [ -z "$(echo "$SEG" | sed 's/[[:space:]]//g')" ] && continue

  if [ "$FIRST" = "1" ]; then
    FIRST=0
    if ! is_readonly_segment "$SEG"; then
      FAIL=1
      break
    fi
  else
    if ! is_readonly_segment "$SEG" && ! is_readonly_filter "$SEG"; then
      FAIL=1
      break
    fi
  fi
done <<< "$SEGMENTS"

# If FIRST is still 1, no segments were found — nothing to allow.
if [ "$FIRST" = "1" ]; then
  exit 0
fi

if [ "$FAIL" = "0" ]; then
  allow "read-only gcloud/terraform pipeline"
fi

exit 0
