"""architect HTTP API (wg0 only, bearer token).

  GET  /health            no auth
  GET  /suggested-gates   dated deadlines from the box's trackers (suggestions only)
  POST /sync              phone pushes a full JSON snapshot
  GET  /state             latest snapshot + when it arrived
"""
from __future__ import annotations

import datetime as dt
import hmac
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request

from . import config, deadlines, store



@asynccontextmanager
async def lifespan(_app):
    config.load_token()  # fail fast if missing
    store.connect(config.DB_FILE).close()
    yield


# No /docs, /redoc or /openapi.json: nothing is readable without the token.
app = FastAPI(title="architect", version="1", lifespan=lifespan,
              docs_url=None, redoc_url=None, openapi_url=None)

MAX_SNAPSHOT_BYTES = 2_000_000


def require_token(authorization: str | None = Header(default=None)) -> None:
    token = config.load_token()
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    if not hmac.compare_digest(authorization[7:].strip().encode(), token.encode()):
        raise HTTPException(401, "bad token")


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/suggested-gates", dependencies=[Depends(require_token)])
def suggested_gates() -> dict:
    items = deadlines.suggested_gates(config.CAREER_DIR, config.ZYCO_DIR, dt.date.today())
    return {"generated": dt.datetime.now().isoformat(timespec="seconds"), "gates": items}


@app.post("/sync", dependencies=[Depends(require_token)])
async def sync(request: Request) -> dict:
    declared = request.headers.get("content-length", "")
    if declared.isdigit() and int(declared) > MAX_SNAPSHOT_BYTES:
        raise HTTPException(413, "snapshot too large")
    raw = await request.body()
    if len(raw) > MAX_SNAPSHOT_BYTES:
        raise HTTPException(413, "snapshot too large")
    try:
        snap = await request.json()
    except Exception:
        raise HTTPException(400, "body is not JSON")
    if not isinstance(snap, dict):
        raise HTTPException(400, "snapshot must be a JSON object")
    for key in ("campaigns", "gates", "quests", "checkins"):
        if key in snap and not isinstance(snap[key], list):
            raise HTTPException(400, f"{key} must be a list")
        if key in snap and not all(isinstance(x, dict) for x in snap[key]):
            raise HTTPException(400, f"every item in {key} must be an object")
    at = store.put_snapshot(config.DB_FILE, snap)
    if at is None:
        # An overlapping older sync arrived late: keep the newer snapshot.
        return {"ok": True, "stale": True}
    return {"ok": True, "receivedAt": at,
            "counts": {k: len(snap.get(k) or []) for k in ("campaigns", "gates", "quests", "checkins")}}


@app.get("/state", dependencies=[Depends(require_token)])
def state() -> dict:
    got = store.latest(config.DB_FILE)
    if not got:
        return {"snapshot": None, "receivedAt": None}
    snap, at = got
    return {"snapshot": snap, "receivedAt": at}
