import plistlib
from datetime import datetime, timezone
from timers import read_timers, active

def _plist(entries):
    return plistlib.dumps({"MTTimers": {"MTTimers": entries}})

def test_reads_an_active_timer():
    data = _plist([{"$MTTimer": {
        "MTTimerID": "A", "MTTimerState": 2, "MTTimerDuration": 3600.0,
        "MTTimerTitle": "Study: Go"}}])
    t = read_timers(data)[0]
    assert t["id"] == "A"
    assert t["state"] == 2
    assert t["title"] == "Study: Go"
    assert t["fired_date"] is None

def test_active_drops_idle_timers():
    data = _plist([
        {"$MTTimer": {"MTTimerID": "A", "MTTimerState": 1}},
        {"$MTTimer": {"MTTimerID": "B", "MTTimerState": 2}},
    ])
    assert [t["id"] for t in active(read_timers(data))] == ["B"]

def test_reads_the_fired_date():
    when = datetime(2026, 8, 7, 6, 30, tzinfo=timezone.utc)
    data = _plist([{"$MTTimer": {
        "MTTimerID": "A", "MTTimerState": 1, "MTTimerFiredDate": when}}])
    assert read_timers(data)[0]["fired_date"] == when


if __name__ == "__main__":
    import traceback
    tests = [test_reads_an_active_timer, test_active_drops_idle_timers, test_reads_the_fired_date]
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
