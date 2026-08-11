from datetime import datetime, timedelta, timezone
from outcome import classify

NOW = datetime(2026, 8, 7, 15, 30, tzinfo=timezone.utc)
END = NOW  # the session was planned to end now

def test_an_active_timer_keeps_running():
    t = {"state": 2, "fired_date": None}
    assert classify(t, END, NOW, idle_seconds=0)[0] == "running"

def test_a_fired_timer_completed():
    t = {"state": 1, "fired_date": NOW}
    state, end = classify(t, END, NOW, idle_seconds=0)
    assert state == "completed"
    assert end == NOW

def test_an_idle_timer_with_no_fired_date_was_cancelled():
    t = {"state": 1, "fired_date": None}
    state, end = classify(t, END, NOW, idle_seconds=0)
    assert state == "cancelled"
    assert end == NOW

def test_an_old_fired_date_does_not_count_as_completed():
    # The timer fired long before the planned end, so it is another timer.
    t = {"state": 1, "fired_date": NOW - timedelta(hours=3)}
    assert classify(t, END, NOW, idle_seconds=0)[0] == "cancelled"

def test_a_missing_timer_was_cancelled():
    assert classify(None, END, NOW, idle_seconds=0)[0] == "cancelled"

def test_a_long_idle_machine_cancels_and_backdates_the_end():
    t = {"state": 2, "fired_date": None}
    state, end = classify(t, END, NOW - timedelta(minutes=10), idle_seconds=3000)
    assert state == "cancelled"
    assert end == NOW - timedelta(minutes=10) - timedelta(seconds=3000)

def test_a_fired_timer_beats_a_long_idle_machine():
    # The user left the desk, but the timer still rang at the planned end.
    # The session ran, so it counts as completed.
    t = {"state": 1, "fired_date": NOW}
    state, end = classify(t, END, NOW, idle_seconds=3000)
    assert state == "completed"
    assert end == NOW

def test_ten_idle_minutes_cancel_a_running_timer():
    t = {"state": 2, "fired_date": None}
    assert classify(t, END, NOW, idle_seconds=700)[0] == "cancelled"

def test_nine_idle_minutes_keep_a_running_timer():
    t = {"state": 2, "fired_date": None}
    assert classify(t, END, NOW, idle_seconds=540)[0] == "running"

def test_a_stale_session_never_logs_past_its_planned_end():
    # The state file sat unread for a day. The end must stay at the planned
    # end, or the note logs 24 hours of study.
    planned = NOW - timedelta(hours=24)
    state, end = classify(None, planned, NOW, idle_seconds=0)
    assert state == "cancelled"
    assert end == planned


if __name__ == "__main__":
    import traceback
    tests = [
        test_an_active_timer_keeps_running,
        test_a_fired_timer_completed,
        test_an_idle_timer_with_no_fired_date_was_cancelled,
        test_an_old_fired_date_does_not_count_as_completed,
        test_a_missing_timer_was_cancelled,
        test_a_long_idle_machine_cancels_and_backdates_the_end,
        test_a_fired_timer_beats_a_long_idle_machine,
        test_ten_idle_minutes_cancel_a_running_timer,
        test_nine_idle_minutes_keep_a_running_timer,
        test_a_stale_session_never_logs_past_its_planned_end,
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
