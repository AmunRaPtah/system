"""SQLite store for phone snapshots and digest bookkeeping (~/.architect/architect.sqlite3)."""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    received_at REAL NOT NULL,
    body TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS kv (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""
KEEP_SNAPSHOTS = 200


def connect(db: Path) -> sqlite3.Connection:
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db)
    con.executescript(SCHEMA)
    return con


def put_snapshot(db: Path, snapshot: dict) -> float:
    now = time.time()
    with connect(db) as con:
        con.execute("INSERT INTO snapshots (received_at, body) VALUES (?, ?)",
                    (now, json.dumps(snapshot, separators=(",", ":"))))
        con.execute("DELETE FROM snapshots WHERE id NOT IN "
                    "(SELECT id FROM snapshots ORDER BY id DESC LIMIT ?)", (KEEP_SNAPSHOTS,))
    return now


def latest(db: Path) -> tuple[dict, float] | None:
    with connect(db) as con:
        row = con.execute("SELECT body, received_at FROM snapshots ORDER BY id DESC LIMIT 1").fetchone()
    return (json.loads(row[0]), row[1]) if row else None


def kv_get(db: Path, key: str) -> str | None:
    with connect(db) as con:
        row = con.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
    return row[0] if row else None


def kv_set(db: Path, key: str, value: str | None) -> None:
    with connect(db) as con:
        if value is None:
            con.execute("DELETE FROM kv WHERE key = ?", (key,))
        else:
            con.execute("INSERT INTO kv (key, value) VALUES (?, ?) "
                        "ON CONFLICT(key) DO UPDATE SET value = excluded.value", (key, value))
