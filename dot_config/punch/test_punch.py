from punch import (parse_distraction, parse_score,
                    parse_pick, advance, step_label,
                    AWAY_DISTRACTION, BACK, STEPS)

OPTIONS = ["Kubernetes", "Terraform", "Go"]


def test_the_picked_item_is_read_by_its_index():
    assert parse_pick("0\n", OPTIONS) == "Kubernetes"
    assert parse_pick("2\n", OPTIONS) == "Go"

def test_a_cancelled_pick_gives_nothing():
    assert parse_pick("skip\n", OPTIONS) is None

def test_a_pick_that_timed_out_gives_nothing():
    # Nobody is at the desk, so no session must start.
    assert parse_pick("timeout\n", OPTIONS) is None

def test_an_index_past_the_list_gives_nothing():
    assert parse_pick("9\n", OPTIONS) is None

def test_a_negative_index_gives_nothing():
    assert parse_pick("-1\n", OPTIONS) is None

def test_an_empty_pick_gives_nothing():
    assert parse_pick("", OPTIONS) is None

def test_the_p_key_asks_for_the_step_before():
    assert parse_pick("back\n", OPTIONS) is BACK


def test_a_step_forward_takes_the_next_number():
    assert advance(1, "Kubernetes") == 2
    assert advance(2, "50") == 3

def test_a_step_back_takes_the_number_before():
    assert advance(3, BACK) == 2
    assert advance(2, BACK) == 1

def test_the_first_step_has_no_step_before_it():
    assert advance(1, BACK) == 1


def test_the_label_names_the_step():
    assert step_label(1, []) == f"Step 1 of {STEPS}"

def test_the_label_shows_what_the_user_picked():
    assert step_label(3, ["Kubernetes", "50 min"]) == (
        f"Step 3 of {STEPS} · Kubernetes · 50 min")

def test_the_label_leaves_out_an_empty_answer():
    assert step_label(2, ["Kubernetes", ""]) == f"Step 2 of {STEPS} · Kubernetes"


def test_the_hud_score_is_read():
    assert parse_score("5\n") == 5

def test_the_hud_key_zero_means_ten():
    # The HUD maps the 0 key to ten, so it prints 10 and not 0.
    assert parse_score("10\n") == 10

def test_a_hud_that_timed_out_takes_the_default_score():
    assert parse_score("timeout\n") == AWAY_DISTRACTION

def test_a_skipped_hud_gives_no_score():
    assert parse_score("skip\n") is None

def test_an_empty_hud_answer_gives_no_score():
    assert parse_score("") is None

def test_a_hud_score_out_of_range_gives_no_score():
    assert parse_score("11\n") is None


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


if __name__ == "__main__":
    import traceback
    tests = [
        test_the_picked_item_is_read_by_its_index,
        test_a_cancelled_pick_gives_nothing,
        test_a_pick_that_timed_out_gives_nothing,
        test_an_index_past_the_list_gives_nothing,
        test_a_negative_index_gives_nothing,
        test_an_empty_pick_gives_nothing,
        test_the_p_key_asks_for_the_step_before,
        test_a_step_forward_takes_the_next_number,
        test_a_step_back_takes_the_number_before,
        test_the_first_step_has_no_step_before_it,
        test_the_label_names_the_step,
        test_the_label_shows_what_the_user_picked,
        test_the_label_leaves_out_an_empty_answer,
        test_the_hud_score_is_read,
        test_the_hud_key_zero_means_ten,
        test_a_hud_that_timed_out_takes_the_default_score,
        test_a_skipped_hud_gives_no_score,
        test_an_empty_hud_answer_gives_no_score,
        test_a_hud_score_out_of_range_gives_no_score,
        test_a_score_is_read_from_the_dialog,
        test_a_score_is_read_when_the_dialog_reports_no_timeout,
        test_a_dialog_that_timed_out_takes_the_default_score,
        test_an_empty_answer_gives_no_score,
        test_a_score_out_of_range_gives_no_score,
        test_a_word_gives_no_score,
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
