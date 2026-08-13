#!/usr/bin/env bash
# Unit tests for zen mode. These cover the arithmetic and the predicates only.
# The font size and the layout need a real Ghostty window, so you must test
# them by hand.
set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/executable_tmux-zen.sh"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}
checkrc() { # label expected_rc actual_rc
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected rc: %s\n      actual rc:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

# If you source the script, it must not touch tmux (no output, exit 0).
out=$( source "$SCRIPT" 2>/dev/null; echo "SOURCED_OK" )
check "source is side-effect free" "SOURCED_OK" "${out##*$'\n'}"

source "$SCRIPT" 2>/dev/null   # bring the pure functions into scope

# --- zen_is_ghostty ------------------------------------------------------
# tmux clobbers TERM_PROGRAM to "tmux", so the client termname is the only
# usable signal.
zen_is_ghostty "xterm-ghostty";   checkrc "xterm-ghostty is Ghostty"      0 "$?"
zen_is_ghostty "ghostty";         checkrc "bare ghostty is Ghostty"       0 "$?"
zen_is_ghostty "screen-256color"; checkrc "tmux termname is not Ghostty"  1 "$?"
zen_is_ghostty "xterm-256color";  checkrc "xterm is not Ghostty"          1 "$?"
zen_is_ghostty "";                checkrc "empty termname is not Ghostty" 1 "$?"

# --- zen_pct -------------------------------------------------------------
check "plain number passes through"   "60" "$(zen_pct 60)"
check "trailing % is stripped"        "60" "$(zen_pct '60%')"
check "empty falls back to default"   "55" "$(zen_pct '')"
check "garbage falls back to default" "55" "$(zen_pct 'wide')"
check "too small falls back"          "55" "$(zen_pct 5)"
check "too large falls back"          "55" "$(zen_pct 99)"
check "lower bound is kept"           "20" "$(zen_pct 20)"
check "upper bound is kept"           "95" "$(zen_pct 95)"

# --- zen_center_cols ----------------------------------------------------
# 272 cols at font 17 becomes about 190 cols at font 24.
check "190 cols at 55%"            "104" "$(zen_center_cols 190 55)"
check "272 cols at 55%"            "149" "$(zen_center_cols 272 55)"
check "190 cols at 70%"            "133" "$(zen_center_cols 190 70)"
check "narrow window clamps up"     "40" "$(zen_center_cols 60 55)"
check "tiny window clamps to width" "30" "$(zen_center_cols 30 55)"

# --- zen_gutter_cols ----------------------------------------------------
# Two columns of the window go to the two pane borders.
check "190/104 leaves 42 a side" "42" "$(zen_gutter_cols 190 104)"
check "272/149 leaves 60 a side" "60" "$(zen_gutter_cols 272 149)"
check "no room gives 1"           "1" "$(zen_gutter_cols 100 96)"
check "negative is floored at 0"  "0" "$(zen_gutter_cols 40 40)"

# --- zen_gutters_fit ----------------------------------------------------
zen_gutters_fit 42; checkrc "42 cols a side fits"      0 "$?"
zen_gutters_fit 6;  checkrc "6 cols a side is the min" 0 "$?"
zen_gutters_fit 5;  checkrc "5 cols a side is too thin" 1 "$?"
zen_gutters_fit 0;  checkrc "0 cols a side is too thin" 1 "$?"
zen_gutters_fit ""; checkrc "empty is too thin"         1 "$?"

# --- zen_session_name ---------------------------------------------------
# tmux session names cannot hold a "." or a ":", so they must be replaced.
check "plain name"          "zen-main-3"      "$(zen_session_name main 3)"
check "dot is replaced"     "zen-my-sess-0"   "$(zen_session_name 'my.sess' 0)"
check "colon is replaced"   "zen-a-b-1"       "$(zen_session_name 'a:b' 1)"
check "hyphen is kept"      "zen-proj-273-2"  "$(zen_session_name 'proj-273' 2)"
check "underscore is kept"  "zen-my_sess-0"   "$(zen_session_name 'my_sess' 0)"

# --- the arithmetic must agree with itself ------------------------------
# The centre plus the two gutters plus the two borders must fill the window,
# give or take the 1 column that integer division can lose.
for w in 120 160 190 220 272 340; do
  c=$(zen_center_cols "$w" 55)
  g=$(zen_gutter_cols "$w" "$c")
  total=$(( c + 2 * g + 2 ))
  slack=$(( w - total ))
  [ "$slack" -ge 0 ] && [ "$slack" -le 1 ] \
    && printf 'ok   - %s cols: centre %s + gutters %sx2 + borders fills the window\n' "$w" "$c" "$g" \
    || { printf 'FAIL - %s cols: centre %s + gutters %sx2 + borders = %s, slack %s\n' "$w" "$c" "$g" "$total" "$slack"; fail=1; }
done

exit "$fail"
