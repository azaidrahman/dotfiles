#!/usr/bin/env bash
# Tests for lesson-log.sh, the hook that mirrors a lesson to an Obsidian note.
#
# The hook reads a transcript and appends callouts to the note that the link
# file names. These tests run it as a subprocess with HOME set to a temp dir,
# so the real link file and the real vault are never touched.
set -u

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for cand in "$BASE/hooks/executable_lesson-log.sh" "$BASE/hooks/lesson-log.sh"; do
  [ -f "$cand" ] && { HOOK="$cand"; break; }
done
HOOK="${HOOK:-$BASE/hooks/lesson-log.sh}"
FIX="$BASE/tests/fixtures/lesson-log"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

[ -f "$HOOK" ] || { echo "FAIL - hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "FAIL - hook has a syntax error"; exit 1; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export HOME="$TMPD/home"
mkdir -p "$HOME/.config" "$TMPD/vault"
NOTE="$TMPD/vault/Flannel.md"
TRANSCRIPT="$FIX/transcript.jsonl"

# The skill writes the frontmatter before the first exchange. Copy only the
# header (up to and including the closing ---, with no blank line after it -
# the append logic below adds that one blank line itself).
sed -n '1,7p' "$FIX/expected.md" > "$NOTE"

run_hook() { # event [transcript]
  printf '{"hook_event_name":"%s","transcript_path":"%s"}' "$1" "${2:-$TRANSCRIPT}" | bash "$HOOK"
}

# 1. Without a link file the hook does nothing.
run_hook Stop
check "no link file: exit 0" "0" "$?"
check "no link file: note untouched" "$(sed -n '1,7p' "$FIX/expected.md")" "$(cat "$NOTE")"

# 2. With a link file the whole transcript is mirrored.
printf '%s\n' "$NOTE" > "$HOME/.config/lesson-log"
run_hook Stop
check "first run: exit 0" "0" "$?"
check "first run: note matches expected" "$(cat "$FIX/expected.md")" "$(cat "$NOTE")"
check "first run: cursor is 14" "14" "$(cat "$HOME/.config/lesson-log.cursor")"
check "first run: skill block stripped" "0" "$(grep -c 'internal noise' "$NOTE")"
check "first run: skill tag stripped" "0" "$(grep -c '<skill' "$NOTE")"
check "first run: owner file set to transcript" "$TRANSCRIPT" "$(head -n1 "$HOME/.config/lesson-log.session")"
check "first run: task-notification not mirrored" "0" "$(grep -c 'task-notification' "$NOTE")"
check "first run: command markup not mirrored" "0" "$(grep -c 'command-message' "$NOTE")"
check "first run: interrupted line not mirrored" "0" "$(grep -c 'Request interrupted' "$NOTE")"

# 3. A second run appends nothing.
run_hook PostToolUse
check "second run: note unchanged" "$(cat "$FIX/expected.md")" "$(cat "$NOTE")"

# 4. A foreign session (different transcript path) is never mirrored, and it
# never advances the cursor, even though the link file still names this note.
FOREIGN="$TMPD/foreign-transcript.jsonl"
cp "$TRANSCRIPT" "$FOREIGN"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"a line from another session"}}' >> "$FOREIGN"
cursor_before="$(cat "$HOME/.config/lesson-log.cursor")"
note_before="$(cat "$NOTE")"
run_hook Stop "$FOREIGN"
check "foreign session: exit 0" "0" "$?"
check "foreign session: note unchanged" "$note_before" "$(cat "$NOTE")"
check "foreign session: cursor unchanged" "$cursor_before" "$(cat "$HOME/.config/lesson-log.cursor")"

# 5. A missing note never blocks the session, and it never creates or
# advances the cursor.
rm "$NOTE"
rm -f "$HOME/.config/lesson-log.cursor"
run_hook Stop
check "missing note: exit 0" "0" "$?"
check "missing note: cursor not created" "1" "$([ -f "$HOME/.config/lesson-log.cursor" ] && echo 0 || echo 1)"

[ "$fail" -eq 0 ] && echo "all tests passed"
exit "$fail"
