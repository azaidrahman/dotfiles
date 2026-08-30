#!/usr/bin/env bash
# lesson-log.sh - mirror a teaching session to an Obsidian note.
#
# The teach skill writes the path of the lesson note to ~/.config/lesson-log.
# While that file exists, this hook appends each new transcript entry to the
# note as an Obsidian callout:
#   - a user prompt              -> [!quote] YOU
#   - assistant prose            -> [!abstract] TUTOR
#   - an AskUserQuestion call    -> one [!question] Question per question,
#                                    each with numbered options
#   - the answers to that call   -> one [!quote] YOU, one line per answer,
#                                    in the same order as the questions
# Tool calls, tool results, and thinking blocks are not mirrored. A user
# prompt is also stripped of <system-reminder> and <skill> blocks.
#
# The hook keeps a cursor in ~/.config/lesson-log.cursor: the count of
# transcript lines that it has already mirrored. Each run reads only the
# lines after the cursor. Hooks of one session run in order, so no lock
# is needed.
#
# The hook never blocks the session. On any problem it writes a warning to
# stderr and exits 0.
set -u

LINK="$HOME/.config/lesson-log"
CURSOR="$HOME/.config/lesson-log.cursor"

[ -f "$LINK" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "lesson-log: jq not found" >&2; exit 0; }

NOTE=$(head -n1 "$LINK")
[ -n "$NOTE" ] && [ -f "$NOTE" ] || { echo "lesson-log: note not found: $NOTE" >&2; exit 0; }

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || { echo "lesson-log: transcript not found" >&2; exit 0; }

start=0
[ -f "$CURSOR" ] && start=$(tr -dc '0-9' < "$CURSOR")
start=${start:-0}
total=$(wc -l < "$TRANSCRIPT" | tr -d ' ')
[ "$total" -gt "$start" ] || exit 0

# Prefix every line of the body with "> ". A bare "> " on its own becomes ">".
callout() { # type title body
  printf '> [!%s] %s\n' "$1" "$2"
  printf '%s\n' "$3" | sed 's/^/> /; s/^> $/>/'
}

# Strip system-injected blocks from a user prompt, then trim blank lines
# at the start and end of the text that remains.
strip_noise() {
  perl -0pe 's/<system-reminder>.*?<\/system-reminder>//gs; s/<skill\b[^>]*>.*?<\/skill>//gs' |
    sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

blocks=""
append() { blocks="${blocks}${blocks:+

}$1"; }

while IFS= read -r line; do
  type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null)
  case "$type" in
    user)
      # A prompt has string content. An answer to AskUserQuestion carries
      # toolUseResult.answers. Other user lines are tool results: skip.
      if [ "$(printf '%s' "$line" | jq -r '.message.content | type')" = "string" ]; then
        text=$(printf '%s' "$line" | jq -r '.message.content' | strip_noise)
        [ -n "$text" ] && append "$(callout quote YOU "$text")"
      fi
      answers=$(printf '%s' "$line" | jq -r '.toolUseResult.answers? // empty | to_entries[]? | .value' 2>/dev/null)
      [ -n "$answers" ] && append "$(callout quote YOU "$answers")"
      ;;
    assistant)
      # Mirror prose and AskUserQuestion calls, in the order they appear in
      # the message. Build each item's callout on its own line in a temp
      # file, because the pipe below runs in a subshell and cannot append
      # to $blocks directly.
      chunk_file=$(mktemp)
      printf '%s' "$line" | jq -c '.message.content[]? | select(.type=="text" or (.type=="tool_use" and .name=="AskUserQuestion"))' 2>/dev/null |
      while IFS= read -r item; do
        if [ "$(printf '%s' "$item" | jq -r '.type')" = "text" ]; then
          text=$(printf '%s' "$item" | jq -r '.text' | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')
          [ -n "$text" ] && { callout abstract TUTOR "$text"; printf '\n'; }
        else
          # One AskUserQuestion call can carry more than one question. Emit
          # one Question callout per question, in order, each separated by
          # one blank line.
          printf '%s' "$item" | jq -c '.input.questions[]?' 2>/dev/null |
          while IFS= read -r q; do
            body=$(printf '%s' "$q" | jq -r '.question, "", (.options | to_entries[] | "\(.key+1). \(.value.label)")')
            callout question Question "$body"; printf '\n'
          done
        fi
      done > "$chunk_file"
      # Drop one trailing blank line so blocks stay separated by exactly one.
      chunk=$(cat "$chunk_file")
      rm -f "$chunk_file"
      [ -n "$chunk" ] && append "$chunk"
      ;;
  esac
done < <(tail -n +"$((start + 1))" "$TRANSCRIPT")

if [ -n "$blocks" ]; then
  current=$(cat "$NOTE")
  if [ -n "$(printf '%s' "$current" | tr -d '[:space:]')" ]; then
    printf '%s\n\n%s\n' "$current" "$blocks" > "$NOTE"
  else
    printf '%s\n' "$blocks" > "$NOTE"
  fi
fi

printf '%s\n' "$total" > "$CURSOR"
exit 0
