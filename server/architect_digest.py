#!/usr/bin/env python3
"""Telegram digests for System v3, run from cron.

  architect_digest.py morning   brief: today's quests (last phone snapshot) + next 3 gates within 14 days
  architect_digest.py evening   reminder, only if the evening gate is not done today
  architect_digest.py check     disuse nudge: one message after 3 days without a gate, then silent
                                until a gate is completed again

Add --dry-run to print the message instead of sending it. One message per run at most
(batched digest, never per-item). Uses the bot in /usr/local/etc/tvbox-alert.env.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from architect import config, store  # noqa: E402

DOMAIN_LABEL = {"body": "Body", "mind": "Mind", "bonds": "Bonds", "ambition": "Ambition",
                "wealth": "Wealth", "ground": "Ground"}


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip().removeprefix("export ").strip()] = v.strip().strip('"').strip("'")
    return env


def send_telegram(text: str) -> None:
    env = load_env(config.TELEGRAM_ENV)
    token, chat = env.get("TELEGRAM_BOT_TOKEN"), env.get("TELEGRAM_CHAT_ID")
    if not token or not chat:
        raise SystemExit(f"telegram credentials missing in {config.TELEGRAM_ENV}")
    data = urllib.parse.urlencode({"chat_id": chat, "text": text,
                                   "disable_web_page_preview": "true"}).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data)
    with urllib.request.urlopen(req, timeout=15) as r:
        body = json.loads(r.read().decode())
    if not body.get("ok"):
        raise SystemExit(f"telegram refused: {body.get('description')}")


def pretty(day: dt.date) -> str:
    return day.strftime("%a %-d %b")


def snapshot() -> tuple[dict, float] | None:
    return store.latest(config.DB_FILE)


def age_line(received_at: float) -> str | None:
    hours = (time.time() - received_at) / 3600
    if hours < 36:
        return None
    return f"(Last phone sync {hours / 24:.0f} days ago; this may be stale.)"


def gates_ahead(snap: dict, today: dt.date) -> list[tuple[dt.date, str]]:
    out = []
    horizon = today + dt.timedelta(days=config.DIGEST_GATE_DAYS)
    for g in snap.get("gates") or []:
        if g.get("done"):
            continue
        try:
            d = dt.date.fromisoformat(str(g.get("date", ""))[:10])
        except ValueError:
            continue
        if today <= d <= horizon:
            camp = g.get("campaignTitle") or ""
            out.append((d, f"{camp}: {g.get('title', '')}" if camp else str(g.get("title", ""))))
    out.sort()
    return out[: config.DIGEST_GATE_COUNT]


def todays_quests(snap: dict, today: dt.date) -> list[dict]:
    key = today.isoformat()
    return [q for q in snap.get("quests") or [] if q.get("dayKey") == key]


def checkins(snap: dict) -> list[dict]:
    return [c for c in snap.get("checkins") or [] if isinstance(c, dict) and c.get("dayKey")]


def morning_message(today: dt.date) -> str | None:
    got = snapshot()
    if not got:
        return None  # silent until the phone has synced at least once
    lines = [f"System, morning brief. {pretty(today)}"]
    snap, at = got
    qs = todays_quests(snap, today)
    if qs:
        lines.append("")
        lines.append(f"Today ({len(qs)}):")
        for q in qs:
            label = DOMAIN_LABEL.get(str(q.get("domain", "")).lower(), "")
            mark = "x" if q.get("done") else " "
            lines.append(f"[{mark}] {label + ': ' if label else ''}{q.get('title', '')}")
    else:
        lines.append("")
        lines.append("No quests set for today yet. The morning gate takes 30 seconds.")
    ahead = gates_ahead(snap, today)
    if ahead:
        lines.append("")
        lines.append(f"Gates in the next {config.DIGEST_GATE_DAYS} days:")
        for d, title in ahead:
            left = (d - today).days
            lines.append(f"- {pretty(d)} ({'today' if left == 0 else f'{left}d'}): {title}")
    stale = age_line(at)
    if stale:
        lines.append("")
        lines.append(stale)
    return "\n".join(lines)


def evening_message(today: dt.date) -> str | None:
    got = snapshot()
    if not got:
        return None
    snap, _ = got
    key = today.isoformat()
    if any(c.get("dayKey") == key and c.get("kind") == "evening" for c in checkins(snap)):
        return None
    qs = todays_quests(snap, today)
    done = sum(1 for q in qs if q.get("done"))
    tail = f" {done}/{len(qs)} quests marked done so far." if qs else ""
    return f"System: the evening gate is open.{tail} Mark each quest done or not and write one line. 30 seconds."


def last_gate_day(snap: dict) -> str | None:
    days = [c["dayKey"] for c in checkins(snap)]
    return max(days) if days else None


def check_message(today: dt.date) -> tuple[str | None, str | None]:
    """(message, marker). The marker is stored once sent so the nudge never repeats for the same lapse."""
    got = snapshot()
    if not got:
        return None, None
    snap, at = got
    last = last_gate_day(snap)
    if last:
        try:
            since = (today - dt.date.fromisoformat(last)).days
        except ValueError:
            return None, None
        marker = last
    else:
        # Never a gate: count from the first snapshot the server has seen.
        first = store.kv_get(config.DB_FILE, "first_snapshot_day")
        if not first:
            first = dt.date.fromtimestamp(at).isoformat()
            store.kv_set(config.DB_FILE, "first_snapshot_day", first)
        since = (today - dt.date.fromisoformat(first)).days
        marker = "never"
    if since < config.DISUSE_DAYS:
        return None, None
    if store.kv_get(config.DB_FILE, "disuse_nudged_for") == marker:
        return None, None
    when = f"since {pretty(dt.date.fromisoformat(last))}" if last else "yet"
    msg = (f"System: no gate {when}. Today is collapsed to one tap: open it, press \"I'm here\", "
           f"and do the one quest on screen. This is the only reminder.")
    return msg, marker


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["morning", "evening", "check"])
    ap.add_argument("--dry-run", action="store_true", help="print instead of sending")
    ap.add_argument("--today", help="override today's date (YYYY-MM-DD), for testing")
    a = ap.parse_args(argv)
    today = dt.date.fromisoformat(a.today) if a.today else dt.date.today()

    marker = None
    if a.mode == "morning":
        msg = morning_message(today)
    elif a.mode == "evening":
        msg = evening_message(today)
    else:
        msg, marker = check_message(today)

    if not msg:
        print(f"{a.mode}: nothing to send")
        return 0
    if a.dry_run:
        print(msg)
        return 0
    send_telegram(msg)
    if marker:
        store.kv_set(config.DB_FILE, "disuse_nudged_for", marker)
    print(f"{a.mode}: sent ({len(msg)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
