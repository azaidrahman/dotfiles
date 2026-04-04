#!/bin/bash
# Auto-allow read-only gcloud and terraform commands
# PreToolUse hook for Bash tool

CMD=$(jq -r '.tool_input.command // ""')

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Skip compound commands (&&, ||, ;, |) - let user decide
if echo "$CMD" | grep -qE '[;&|]'; then
  exit 0
fi

# --- gcloud read-only commands ---
if echo "$CMD" | grep -qE '^\s*gcloud\b'; then
  # Strip flags and quoted strings to isolate command words
  CLEAN=$(echo "$CMD" | sed "s/ --[^ ]*//g; s/ -[a-zA-Z][^ ]*//g; s/\"[^\"]*\"//g; s/'[^']*'//g")
  VERB=$(echo "$CLEAN" | tr -s ' ' '\n' | grep -xE 'list|describe|get-iam-policy|get-value|read|export|info' | head -1)
  if [ -n "$VERB" ]; then
    allow "read-only gcloud: $VERB"
  fi
fi

# --- terraform read-only commands ---
if echo "$CMD" | grep -qE '^\s*terraform\b'; then
  SUBCMD=$(echo "$CMD" | awk '{print $2}')
  case "$SUBCMD" in
    plan|show|output|validate|fmt|version|providers|graph|init)
      allow "read-only terraform: $SUBCMD"
      ;;
    state)
      SUBCMD2=$(echo "$CMD" | awk '{print $3}')
      case "$SUBCMD2" in
        list|show|pull)
          allow "read-only terraform: state $SUBCMD2"
          ;;
      esac
      ;;
    workspace)
      SUBCMD2=$(echo "$CMD" | awk '{print $3}')
      case "$SUBCMD2" in
        list|show)
          allow "read-only terraform: workspace $SUBCMD2"
          ;;
      esac
      ;;
  esac
fi
