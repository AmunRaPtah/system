#!/usr/bin/env python3
"""Cross-check the poker hand evaluator against `treys` (pip install treys).

`evaluate` is a line-for-line port of HandEvaluator.evaluate(mask:) in
ios/System/Services/Poker/PokerCore.swift. The check:
  1. random 5/6/7-card hands: our value order must equal treys' order exactly
     (same ties, same winners), via a strictly monotone value -> treys map;
  2. random head-to-head showdowns on a shared board;
  3. the PokerSelfTest table parsed out of the Swift file, against both.
Usage: python3 tools/check_poker_eval.py [N]   (default N = 200000)
"""
import random
import re
import sys
from pathlib import Path

from treys import Card as TCard, Evaluator

RANKS = "23456789TJQKA"
SUITS = "shdc"
SWIFT = Path(__file__).resolve().parent.parent / "ios/System/Services/Poker/PokerCore.swift"


def bit(card):
    return 1 << (SUITS.index(card[1]) * 16 + RANKS.index(card[0]) + 2)


def mask(cards):
    m = 0
    for c in cards:
        m |= bit(c)
    return m


def highest(m):
    return m.bit_length() - 1


def top(m, n):
    out, r = [], 14
    while r >= 2 and len(out) < n:
        if m & (1 << r):
            out.append(r)
        r -= 1
    return out


def pack(cat, ranks):
    v = 0
    for i in range(5):
        v = v << 4 | (ranks[i] if i < len(ranks) else 0)
    return cat << 20 | v


def straight_high(ranks):
    m = ranks
    if m & (1 << 14):
        m |= 1 << 1
    high = 14
    while high >= 5:
        w = 0x1F << (high - 4)
        if m & w == w:
            return high
        high -= 1
    return 0


def evaluate(m):
    s0, s1 = m & 0xFFFF, (m >> 16) & 0xFFFF
    s2, s3 = (m >> 32) & 0xFFFF, (m >> 48) & 0xFFFF
    any_ = s0 | s1 | s2 | s3
    quads = s0 & s1 & s2 & s3
    trips = (s0 & s1 & s2) | (s0 & s1 & s3) | (s0 & s2 & s3) | (s1 & s2 & s3)
    pairs = (s0 & s1) | (s0 & s2) | (s0 & s3) | (s1 & s2) | (s1 & s3) | (s2 & s3)

    flush = 0
    for s in (s0, s1, s2, s3):
        if bin(s).count("1") >= 5:
            sf = straight_high(s)
            if sf > 0:
                return pack(8, [sf])
            flush = s
    if quads:
        q = highest(quads)
        return pack(7, [q] + top(any_ & ~(1 << q), 1))
    if trips:
        t = highest(trips)
        rest = pairs & ~(1 << t)
        if rest:
            return pack(6, [t, highest(rest)])
    if flush:
        return pack(5, top(flush, 5))
    st = straight_high(any_)
    if st > 0:
        return pack(4, [st])
    if trips:
        t = highest(trips)
        return pack(3, [t] + top(any_ & ~(1 << t), 2))
    if pairs:
        p1 = highest(pairs)
        rest = pairs & ~(1 << p1)
        if rest:
            p2 = highest(rest)
            return pack(2, [p1, p2] + top(any_ & ~(1 << p1) & ~(1 << p2), 1))
        return pack(1, [p1] + top(any_ & ~(1 << p1), 3))
    return pack(0, top(any_, 5))


EV = Evaluator()


def treys(cards):
    t = [TCard.new(c) for c in cards]
    return EV.evaluate(t[:2], t[2:])  # lower is better


DECK = [r + s for r in RANKS for s in SUITS]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200000
    rng = random.Random(7)
    fails = 0

    seen = {}
    for size in (5, 6, 7):
        for _ in range(n // 3):
            hand = rng.sample(DECK, size)
            ours, theirs = evaluate(mask(hand)), treys(hand)
            prev = seen.setdefault(ours, theirs)
            if prev != theirs:
                fails += 1
                if fails < 10:
                    print("tie mismatch", hand, hex(ours), prev, theirs)
    order = [seen[k] for k in sorted(seen)]
    bad_order = sum(1 for a, b in zip(order, order[1:]) if not a > b)
    fails += bad_order
    print(f"[1] {n // 3 * 3} hands, {len(seen)} distinct values, order violations: {bad_order}")

    shows = 0
    for _ in range(n // 4):
        cards = rng.sample(DECK, 9)
        board, a, b = cards[:5], cards[5:7], cards[7:]
        x, y = evaluate(mask(a + board)), evaluate(mask(b + board))
        tx, ty = treys(a + board), treys(b + board)
        if (x > y) != (tx < ty) or (x == y) != (tx == ty):
            shows += 1
            if shows < 10:
                print("showdown mismatch", a, b, board)
    fails += shows
    print(f"[2] {n // 4} showdowns, mismatches: {shows}")

    rows = re.findall(r'\("([2-9TJQKA][shdc](?: [2-9TJQKA][shdc]){6})", "([<>=])", "([^"]+)"\)', SWIFT.read_text())
    table = 0
    for a, op, b in rows:
        a, b = a.split(), b.split()
        x, y, tx, ty = evaluate(mask(a)), evaluate(mask(b)), treys(a), treys(b)
        want = {">": (x > y, tx < ty), "<": (x < y, tx > ty), "=": (x == y, tx == ty)}[op]
        if not all(want):
            table += 1
            print("table row fails", a, op, b, want)
    fails += table
    print(f"[3] {len(rows)} self-test rows from PokerCore.swift, failures: {table}")

    print("OK" if fails == 0 and len(rows) >= 20 else "FAIL")
    return 0 if fails == 0 and len(rows) >= 20 else 1


if __name__ == "__main__":
    sys.exit(main())
