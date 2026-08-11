from session import parse_distraction, parse_choice, AWAY_DISTRACTION


def test_a_score_is_read_from_the_dialog():
    assert parse_distraction("button returned:OK, text returned:4") == 4

def test_a_score_is_read_when_the_dialog_reports_no_timeout():
    out = "button returned:OK, text returned:4, gave up:false"
    assert parse_distraction(out) == 4

def test_a_dialog_that_timed_out_takes_the_default_score():
    out = "button returned:, text returned:, gave up:true"
    assert parse_distraction(out) == AWAY_DISTRACTION

def test_an_empty_answer_gives_no_score():
    assert parse_distraction("button returned:OK, text returned:") is None

def test_a_score_out_of_range_gives_no_score():
    assert parse_distraction("button returned:OK, text returned:11") is None

def test_a_word_gives_no_score():
    assert parse_distraction("button returned:OK, text returned:lots") is None


def test_the_end_button_ends_the_session():
    assert parse_choice("button returned:End & log") == "end"

def test_the_discard_button_discards_the_session():
    assert parse_choice("button returned:Discard") == "discard"

def test_the_keep_button_keeps_the_session():
    assert parse_choice("button returned:Keep it") == "keep"

def test_an_unknown_button_keeps_the_session():
    # A closed dialog must never destroy an open session.
    assert parse_choice("") == "keep"


if __name__ == "__main__":
    import traceback
    tests = [
        test_a_score_is_read_from_the_dialog,
        test_a_score_is_read_when_the_dialog_reports_no_timeout,
        test_a_dialog_that_timed_out_takes_the_default_score,
        test_an_empty_answer_gives_no_score,
        test_a_score_out_of_range_gives_no_score,
        test_a_word_gives_no_score,
        test_the_end_button_ends_the_session,
        test_the_discard_button_discards_the_session,
        test_the_keep_button_keeps_the_session,
        test_an_unknown_button_keeps_the_session,
    ]
    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            print(f"✓ {test.__name__}")
            passed += 1
        except Exception as e:
            print(f"✗ {test.__name__}: {e}")
            traceback.print_exc()
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    exit(0 if failed == 0 else 1)
