"""Paths and settings. Everything is overridable by env var so tests can point at a temp dir."""
from __future__ import annotations

import os
from pathlib import Path

HOME = Path(os.environ.get("ARCHITECT_HOME", str(Path.home() / ".architect")))
TOKEN_FILE = HOME / "token"
DB_FILE = HOME / "architect.sqlite3"

CAREER_DIR = Path(os.environ.get("ARCHITECT_CAREER_DIR", "/root/application-career"))
ZYCO_DIR = Path(os.environ.get("ARCHITECT_ZYCO_DIR", "/root/zyco"))
TELEGRAM_ENV = Path(os.environ.get("ARCHITECT_TELEGRAM_ENV", "/usr/local/etc/tvbox-alert.env"))

# How far ahead the digest looks for gates, and how many it lists.
DIGEST_GATE_DAYS = 14
DIGEST_GATE_COUNT = 3
# Days without a completed gate before the one-off disuse nudge (matches the app).
DISUSE_DAYS = 3


def load_token() -> str:
    if not TOKEN_FILE.exists():
        raise RuntimeError(f"token file missing: {TOKEN_FILE}")
    tok = TOKEN_FILE.read_text().strip()
    if not tok:
        raise RuntimeError(f"token file empty: {TOKEN_FILE}")
    return tok
