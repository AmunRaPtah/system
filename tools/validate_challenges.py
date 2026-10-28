#!/usr/bin/env python3
"""Validate challenges.json against CONTENT_SCHEMA.md rules."""
import os
import json, sys, collections

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "System", "Resources", "Content", "challenges.json")

REQUIRED = ["id", "title", "pillar", "stat", "cadence", "difficulty",
            "minutes", "instructions", "why", "source", "proof"]
PILLARS = {"body", "mind", "social", "sovereign"}
STATS = {"STR", "END", "AGI", "VIT", "PER", "INT", "WIL", "CHA", "SOV"}
CADENCES = {"daily", "weekly", "monthly"}
PROOFS = {"check", "note", "count"}

def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)

with open(PATH) as f:
    data = json.load(f)

if "version" not in data or "challenges" not in data:
    fail("missing top-level version/challenges keys")

challenges = data["challenges"]
ids = []
errors = []

for c in challenges:
    cid = c.get("id", "<no-id>")
    for key in REQUIRED:
        if key not in c:
            errors.append(f"{cid}: missing key '{key}'")
    if "pillar" in c and c["pillar"] not in PILLARS:
        errors.append(f"{cid}: bad pillar {c['pillar']}")
    if "stat" in c and c["stat"] not in STATS:
        errors.append(f"{cid}: bad stat {c['stat']}")
    if "cadence" in c and c["cadence"] not in CADENCES:
        errors.append(f"{cid}: bad cadence {c['cadence']}")
    if "proof" in c and c["proof"] not in PROOFS:
        errors.append(f"{cid}: bad proof {c['proof']}")
    if "difficulty" in c and not (1 <= c["difficulty"] <= 5):
        errors.append(f"{cid}: bad difficulty {c['difficulty']}")
    if "title" in c and len(c["title"]) > 40:
        errors.append(f"{cid}: title too long ({len(c['title'])} chars)")
    ids.append(cid)

dupes = [i for i, n in collections.Counter(ids).items() if n > 1]
if dupes:
    errors.append(f"duplicate ids: {dupes}")

general_count = sum(1 for c in challenges if c.get("source") == "general")
if challenges and general_count / len(challenges) > 0.15:
    errors.append(f"too many 'general' sources: {general_count}/{len(challenges)}")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)

print(f"OK: {len(challenges)} challenges valid\n")

by_pillar = collections.Counter(c["pillar"] for c in challenges)
by_cadence = collections.Counter(c["cadence"] for c in challenges)
by_diff = collections.Counter(c["difficulty"] for c in challenges)

print("By pillar:", dict(sorted(by_pillar.items())))
print("By cadence:", dict(sorted(by_cadence.items())))
print("By difficulty:", dict(sorted(by_diff.items())))
