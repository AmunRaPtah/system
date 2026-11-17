"""HTTP API: auth, /sync round-trip, /suggested-gates shape; digest silence rules."""
import datetime as dt
import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("ARCHITECT_HOME", str(tmp_path))
    (tmp_path / "token").write_text("t0ken\n")
    from architect import config, main
    importlib.reload(config)
    importlib.reload(main)
    return config, main


def auth(tok="t0ken"):
    return {"Authorization": f"Bearer {tok}"}


SNAP = {
    "schema": 1, "sentAt": "2026-11-17T08:00:00Z",
    "campaigns": [{"id": "c1", "title": "Neurocascade funded", "status": "active"}],
    "gates": [{"id": "g1", "campaignId": "c1", "campaignTitle": "Neurocascade funded",
               "title": "DFG draft", "date": "2026-11-25", "done": False}],
    "quests": [{"id": "q1", "title": "Write aims page", "domain": "ambition",
                "dayKey": "2026-11-17", "done": False}],
    "checkins": [{"dayKey": "2026-11-17", "kind": "morning", "energy": 4, "line": "ship it"}],
}


def test_auth_required(env):
    _, main = env
    with TestClient(main.app) as c:
        assert c.get("/health").json() == {"ok": True}
        assert c.get("/state").status_code == 401
        assert c.get("/state", headers=auth("wrong")).status_code == 401
        assert c.post("/sync", json=SNAP).status_code == 401


def test_sync_round_trip(env):
    _, main = env
    with TestClient(main.app) as c:
        assert c.get("/state", headers=auth()).json()["snapshot"] is None
        r = c.post("/sync", json=SNAP, headers=auth())
        assert r.status_code == 200
        assert r.json()["counts"] == {"campaigns": 1, "gates": 1, "quests": 1, "checkins": 1}
        s = c.get("/state", headers=auth()).json()
        assert s["snapshot"] == SNAP and s["receivedAt"] > 0
        newer = dict(SNAP, quests=[])
        c.post("/sync", json=newer, headers=auth())
        assert c.get("/state", headers=auth()).json()["snapshot"]["quests"] == []
        assert c.post("/sync", json=[1], headers=auth()).status_code == 400
        assert c.post("/sync", json={"gates": "x"}, headers=auth()).status_code == 400


def test_suggested_gates_shape(env):
    _, main = env
    with TestClient(main.app) as c:
        r = c.get("/suggested-gates", headers=auth())
        assert r.status_code == 200
        for g in r.json()["gates"]:
            assert {"title", "date", "source", "domain"} <= set(g)


def test_digest_silent_until_first_sync(env, capsys):
    config, main = env
    import architect_digest as d
    importlib.reload(d)
    today = dt.date(2026, 11, 17)
    assert d.morning_message(today) is None
    assert d.evening_message(today) is None
    assert d.check_message(today) == (None, None)
    with TestClient(main.app) as c:
        c.post("/sync", json=SNAP, headers=auth())
    m = d.morning_message(today)
    assert "Write aims page" in m and "DFG draft" in m
    assert d.evening_message(today) is not None          # morning gate only, evening open
    done = dict(SNAP, checkins=SNAP["checkins"] + [{"dayKey": "2026-11-17", "kind": "evening"}])
    with TestClient(main.app) as c:
        c.post("/sync", json=done, headers=auth())
    assert d.evening_message(today) is None
    # Disuse: 3 days after the last gate, nudge once, then silent for the same lapse.
    later = dt.date(2026, 11, 20)
    msg, marker = d.check_message(later)
    assert msg and marker == "2026-11-17"
    from architect import store
    store.kv_set(config.DB_FILE, "disuse_nudged_for", marker)
    assert d.check_message(dt.date(2026, 11, 21)) == (None, None)
    assert d.check_message(dt.date(2026, 11, 18))[0] is None
