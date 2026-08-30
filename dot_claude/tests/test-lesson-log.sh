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
# header (up to and including the closing --- and the blank line after it).
sed -n '1,8p' "$FIX/expected.md" > "$NOTE"

run_hook() { # event
  printf '{"hook_event_name":"%s","transcript_path":"%s"}' "$1" "$TRANSCRIPT" | bash "$HOOK"
}

# 1. Without a link file the hook does nothing.
run_hook Stop
check "no link file: exit 0" "0" "$?"
check "no link file: note untouched" "$(sed -n '1,8p' "$FIX/expected.md")" "$(cat "$NOTE")"

# 2. With a link file the whole transcript is mirrored.
printf '%s\n' "$NOTE" > "$HOME/.config/lesson-log"
run_hook Stop
check "first run: exit 0" "0" "$?"
check "first run: note matches expected" "$(cat "$FIX/expected.md")" "$(cat "$NOTE")"
check "first run: cursor is 5" "5" "$(cat "$HOME/.config/lesson-log.cursor")"

# 3. A second run appends nothing.
run_hook PostToolUse
check "second run: note unchanged" "$(cat "$FIX/expected.md")" "$(cat "$NOTE")"

# 4. A missing note never blocks the session.
rm "$NOTE"
run_hook Stop
check "missing note: exit 0" "0" "$?"

[ "$fail" -eq 0 ] && echo "all tests passed"
exit "$fail"
