from resync import commands, result_text


def test_the_first_command_clears_the_script_state():
    first = commands()[0]
    assert first[:3] == ["chezmoi", "state", "delete-bucket"]
    assert "--bucket=scriptState" in first


def test_the_last_command_applies_the_source():
    assert commands()[-1] == ["chezmoi", "update"]


def test_the_clear_comes_before_the_apply():
    # An apply that runs first records the hashes again, and every hook
    # stays gated. The order is the whole point of the resync.
    names = [c[1] for c in commands()]
    assert names.index("state") < names.index("update")


def test_a_run_that_ends_well_reports_done():
    assert result_text(0) == "resync done"


def test_a_run_that_fails_reports_the_failure():
    assert result_text(1) == "resync failed"
    assert result_text(2) == "resync failed"


class _Result:
    def __init__(self, returncode):
        self.returncode = returncode
        self.stderr = ""


def _record(monkeypatch, codes):
    """Run main() with stubbed commands. Return the calls and the toasts."""
    import resync
    calls, toasts = [], []
    codes = list(codes)

    def fake_run(command, **kwargs):
        calls.append(command)
        return _Result(codes.pop(0))

    monkeypatch.setattr(resync.subprocess, "run", fake_run)
    monkeypatch.setattr(resync, "toast", toasts.append)
    return calls, toasts, resync.main()


def test_a_clean_run_runs_every_command(monkeypatch):
    calls, _, code = _record(monkeypatch, [0, 0])
    assert len(calls) == 2
    assert code == 0


def test_a_failed_clear_stops_the_resync(monkeypatch):
    # An update after a failed clear leaves every hook gated, and the
    # toast would report a success that did not happen.
    calls, _, code = _record(monkeypatch, [1, 0])
    assert len(calls) == 1
    assert code == 1


def test_the_toasts_report_the_start_and_the_result(monkeypatch):
    _, toasts, _ = _record(monkeypatch, [0, 0])
    assert toasts == ["resync started", "resync done"]


def test_a_failure_reaches_the_toast(monkeypatch):
    _, toasts, _ = _record(monkeypatch, [0, 3])
    assert toasts[-1] == "resync failed"
