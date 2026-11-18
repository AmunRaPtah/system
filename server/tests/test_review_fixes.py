"""Regression tests for the 2026-11-18 review of Phase 1."""
import datetime as dt

from fastapi.testclient import TestClient

from architect import deadlines
from test_api import SNAP, auth, env  # noqa: F401  (fixture re-export)

TODAY = dt.date(2026, 11, 18)


def test_year_inference_prefers_future():
    p = deadlines.parse_day_month
    assert p("1 Jun", TODAY) == (dt.date(2027, 6, 1), False)      # was dropped as 2026-06-01
    assert p("3 Nov", TODAY) == (dt.date(2026, 11, 3), False)     # just missed: stays in the past
    assert p("29 Feb", TODAY) is None                             # impossible date, no crash


def test_bad_rows_do_not_break_the_feed(tmp_path):
    career, zyco = tmp_path / "career", tmp_path / "zyco"
    career.mkdir(); zyco.mkdir()
    (career / "README.md").write_text(
        "| Deadline | Application | Type | Status |\n|---|---|---|---|\n"
        "| 1 Dec | Good fellowship | Fellowship | Not started |\n"
        "| 5 Dec | Already in | Job | Submitted 12 Oct |\n")   # mixed-case done word
    (zyco / "OPPORTUNITIES.md").write_text(
        "## topologix (x)\n| Opportunity (link) | Deadline | Confidence |\n|---|---|---|\n"
        "| Broken date grant | 2026-02-30 | page-confirmed |\n"
        "| Real grant for young... | 2026-12-10 | page-confirmed |\n")
    (zyco / "PORTFOLIO.md").write_text(
        "| Division | Next milestone |\n|---|---|\n| x | thing (2026-13-01) |\n")
    got = deadlines.suggested_gates(career, zyco, TODAY)
    titles = [g["title"] for g in got]
    assert "Good fellowship" in titles
    assert not any("Already in" in t for t in titles)
    assert "topologix: Real grant for young…" in titles   # truncation stays visible
    assert not any("Broken" in t for t in titles)


def test_ticked_checklist_hides_readme_twin(tmp_path):
    career, zyco = tmp_path / "career", tmp_path / "zyco"
    career.mkdir(); zyco.mkdir()
    (career / "CHECKLIST.md").write_text("## December 2026\n- [x] **1 Dec** **PhD**, Potsdam doctoral form\n")
    (career / "README.md").write_text(
        "| Deadline | Application | Type | Status |\n|---|---|---|---|\n"
        "| 1 Dec | Potsdam doctoral form | PhD | Not started |\n")
    assert deadlines.suggested_gates(career, zyco, TODAY) == []


def test_sync_rejects_bad_items_and_older_snapshots(env):  # noqa: F811
    _, main = env
    with TestClient(main.app) as c:
        assert c.post("/sync", json=dict(SNAP, quests=[1]), headers=auth()).status_code == 400
        assert c.post("/sync", json=SNAP, headers=auth()).status_code == 200
        older = dict(SNAP, sentAt="2026-11-17T07:00:00Z", quests=[])
        r = c.post("/sync", json=older, headers=auth())
        assert r.status_code == 200 and r.json().get("stale") is True
        assert c.get("/state", headers=auth()).json()["snapshot"]["quests"] == SNAP["quests"]
        assert c.get("/docs").status_code == 404
        assert c.get("/openapi.json").status_code == 404


def test_disuse_nudge_survives_check_in_window(env):  # noqa: F811
    config, main = env
    import importlib
    import architect_digest as d
    importlib.reload(d)
    with TestClient(main.app) as c:
        c.post("/sync", json=SNAP, headers=auth())          # last gate 2026-11-17
        msg, marker = d.check_message(dt.date(2026, 11, 21))
        assert marker == "2026-11-17" and "since" in msg
        d.store.kv_set(config.DB_FILE, "disuse_nudged_for", marker)
        # 40 days on, the phone's 30-day window holds no check-ins any more.
        c.post("/sync", json=dict(SNAP, sentAt="2026-12-27T08:00:00Z", checkins=[]), headers=auth())
        assert d.check_message(dt.date(2026, 12, 27)) == (None, None)   # no second "no gate yet"


def test_today_follows_phone_timezone(env):  # noqa: F811
    _, main = env
    import importlib
    import architect_digest as d
    importlib.reload(d)
    with TestClient(main.app) as c:
        c.post("/sync", json=dict(SNAP, tz="Pacific/Kiritimati"), headers=auth())
        from zoneinfo import ZoneInfo
        assert d.owner_today() == dt.datetime.now(ZoneInfo("Pacific/Kiritimati")).date()
