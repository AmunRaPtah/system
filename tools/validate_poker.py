"""Validate lessons-poker.json.

Usage: python validate_poker.py [lessons-poker.json] [--samples N]
Needs treys (MIT) for hand evaluation. Besides the shared schema checks:
  - every numeric quiz question is recognised by its prompt template and its
    marked answer is recomputed from scratch (pot odds, bluff break-even, rule
    of 2/4, exact hit odds, outs counted card-by-card with the evaluator, exact
    river win odds over all 44 cards, EV of a call, bankroll and buy-in maths,
    combination counts by enumeration, best-hand class, showdown winner);
    the computed value must equal the marked answer and no distractor
  - preflop equities are re-simulated (Monte Carlo, default 20k deals): the
    marked answer must be within 2 points and every distractor at least 6 away
  - numeric claims in lesson bodies (odds tables, combo counts, examples) are
    recomputed and must appear in the body text
Questions that match no template are conceptual and are only schema-checked.
"""
import random, re, sys
from itertools import combinations
from math import comb
from treys import Card, Evaluator
from validate_common import Report, check_schema, path_for

EV = Evaluator()
FULL = [r + s for r in '23456789TJQKA' for s in 'shdc']
SUIT = {'♠': 's', '♥': 'h', '♦': 'd', '♣': 'c'}
CLASS = {1: 'Straight flush', 2: 'Four of a kind', 3: 'Full house', 4: 'Flush', 5: 'Straight',
         6: 'Three of a kind', 7: 'Two pair', 8: 'One pair', 9: 'High card'}
TARGET = {'a straight flush': 1, 'four of a kind': 2, 'a full house': 3, 'a flush': 4,
          'a straight': 5, 'three of a kind': 6, 'two pair': 7}


def cards(text):
    out = []
    for t in text.split():
        rank, suit = t[:-1], t[-1]
        out.append(('T' if rank == '10' else rank) + SUIT[suit])
    assert all(c in FULL for c in out) and len(set(out)) == len(out), text
    return out


def pct(x):
    return f"{round(x * 100, 1):g}%"


def money(v, sign=True):
    v = round(v, 2)
    s = f"{abs(v):.2f}".rstrip('0').rstrip('.')
    return (("+" if v > 0 else "-" if v < 0 else "") if sign else ("-" if v < 0 else "")) + "$" + s


def score(board, hole):
    return EV.evaluate([Card.new(c) for c in board], [Card.new(c) for c in hole])


def combos(text):
    def m(h):
        r1, r2 = h[0][0], h[1][0]; s = h[0][1] == h[1][1]
        return {'a specific pocket pair such as A-A': r1 == r2 == 'A',
                'A-K suited': {r1, r2} == {'A', 'K'} and s,
                'A-K offsuit': {r1, r2} == {'A', 'K'} and not s,
                'A-K (suited and offsuit together)': {r1, r2} == {'A', 'K'},
                'all two-card starting hands': True}[text]
    return str(sum(1 for h in combinations(FULL, 2) if m(h)))


def mc_equity(h1, h2, n, rng):
    rest = [c for c in FULL if c not in h1 + h2]
    a = [Card.new(c) for c in h1]; b = [Card.new(c) for c in h2]
    pool = [Card.new(c) for c in rest]
    tot = 0.0
    for _ in range(n):
        bd = rng.sample(pool, 5)
        x, y = EV.evaluate(bd, a), EV.evaluate(bd, b)
        tot += 1 if x < y else 0.5 if x == y else 0
    return 100 * tot / n


def compute(prompt):
    """Return ('exact', value) or ('approx', equity) or None if not a templated question."""
    P = re.match
    if m := P(r'The pot is \$(\d+)\. Your opponent bets \$(\d+)\. What equity do you need to break even on a call\?$', prompt):
        p, b = map(int, m.groups()); return 'exact', pct(b / (p + 2 * b))
    if m := P(r'You bet \$(\d+) into a \$(\d+) pot as a pure bluff that never wins when called\. How often must your opponent fold', prompt):
        b, p = map(int, m.groups()); return 'exact', pct(b / (p + b))
    if m := P(r'You are all-in on the flop with (\d+) outs, so you will see the turn and the river\. What does the rule of 4', prompt):
        return 'exact', f'{4 * int(m.group(1))}%'
    if m := P(r'On the turn you have (\d+) outs with one card to come\. What does the rule of 2', prompt):
        return 'exact', f'{2 * int(m.group(1))}%'
    if m := P(r'You are all-in on the flop with (\d+) clean outs among 47 unseen cards\. What is the exact chance', prompt):
        n = int(m.group(1)); return 'exact', pct(1 - comb(47 - n, 2) / comb(47, 2))
    if m := P(r'On the turn you have (\d+) clean outs among 46 unseen cards\. What is the exact chance', prompt):
        return 'exact', pct(int(m.group(1)) / 46)
    if m := P(r'You hold (.+?) and the flop is (.+?)\. How many of the 47 unseen cards give you (.+?) or better on the turn\?$', prompt):
        h, f = cards(m.group(1)), cards(m.group(2)); cls = TARGET[m.group(3)]
        unseen = [c for c in FULL if c not in h + f]
        assert len(unseen) == 47
        return 'exact', str(sum(1 for c in unseen if EV.get_rank_class(score(f + [c], h)) <= cls))
    if m := P(r'You hold (.+?), your opponent holds (.+?), and the turn board is (.+?)\. What is your exact chance to win outright on the river\?$', prompt):
        a, b, bd = cards(m.group(1)), cards(m.group(2)), cards(m.group(3))
        rest = [c for c in FULL if c not in a + b + bd]
        assert len(rest) == 44
        w = sum(1 for c in rest if score(bd + [c], a) < score(bd + [c], b))
        return 'exact', pct(w / 44)
    if m := P(r'The pot is \$(\d+) and your opponent bets \$(\d+)\. Your equity is (\d+)%\. What is the expected value of calling', prompt):
        p, b, e = map(int, m.groups()); e /= 100
        return 'exact', money(e * (p + b) - (1 - e) * b)
    if m := P(r'Your poker bankroll is \$(\d+)\. You follow a (\d+)-buy-in rule for cash games\. What is the largest buy-in', prompt):
        x, k = map(int, m.groups()); return 'exact', money(x / k, sign=False)
    if m := P(r'Your bankroll is \$(\d+) and each buy-in is \$(\d+)\. How many buy-ins', prompt):
        x, b = map(int, m.groups()); return 'exact', f'{x / b:g}'
    if m := P(r'How many card combinations are there for (.+)\?$', prompt):
        return 'exact', combos(m.group(1))
    if m := P(r'All-in preflop, (.+?) against (.+?)\. Roughly what is the equity of (.+?)\?$', prompt):
        assert m.group(1) == m.group(3)
        return 'approx', (cards(m.group(1)), cards(m.group(2)))
    if m := P(r'The board is (.+?) and you hold (.+?)\. What is your best five-card hand\?$', prompt):
        return 'exact', CLASS[EV.get_rank_class(score(cards(m.group(1)), cards(m.group(2))))]
    if m := P(r'The board is (.+?)\. (Player 1 holds .+)\. Who wins\?$', prompt):
        bd = cards(m.group(1))
        hands = [cards(x) for x in re.findall(r'Player \d holds (.+?)(?:,|$)', m.group(2))]
        sc = [score(bd, h) for h in hands]
        win = [i for i, s in enumerate(sc) if s == min(sc)]
        return 'exact', f'Player {win[0] + 1}' if len(win) == 1 else 'Split pot'
    return None


def body_facts():
    """(lesson id, text that must appear in the body, recomputed value, expected value)."""
    c47 = comb(47, 2)
    hit2 = lambda n: 1 - comb(47 - n, 2) / c47
    setflop = 1 - comb(48, 3) / comb(50, 3)
    flushflop = comb(11, 3) / comb(50, 3)
    miss = comb(44, 3) / comb(50, 3)
    return [
        ('poker-u1-l5', '1,326', comb(52, 2), 1326),
        ('poker-u1-l5', '1 in 17', round(comb(52, 2) / (13 * 6)), 17),
        ('poker-u1-l5', '1 in 221', round(comb(52, 2) / 6), 221),
        ('poker-u1-l5', 'about 5.9%', pct(13 * 6 / comb(52, 2)), '5.9%'),
        ('poker-u1-l5', 'about 11.8%', pct(setflop), '11.8%'),
        ('poker-u1-l5', '**12** combinations', comb(4, 1) * 3 * 4 // 4 * 1, 12),
        ('poker-u2-l4', 'less than 1%', flushflop < 0.01, True),
        ('poker-u2-l4', 'about 1 in 8.5', round(1 / setflop, 1), 8.5),
        ('poker-u3-l2', '18% (exact 19.1%)', pct(9 / 47), '19.1%'),
        ('poker-u3-l2', '36% (exact 35.0%)', f'{hit2(9) * 100:.1f}%', '35.0%'),
        ('poker-u3-l2', '16% (17.0%)', f'{8 / 47 * 100:.1f}%', '17.0%'),
        ('poker-u3-l2', '32% (31.5%)', pct(hit2(8)), '31.5%'),
        ('poker-u3-l2', '8% (8.5%)', pct(4 / 47), '8.5%'),
        ('poker-u3-l2', '16% (16.5%)', pct(hit2(4)), '16.5%'),
        ('poker-u3-l2', 'exact figure is about 54%', round(hit2(15) * 100), 54),
        ('poker-u3-l3', 'C(38, 2) = 703', comb(38, 2), 703),
        ('poker-u3-l3', 'C(47, 2) = 1,081', c47, 1081),
        ('poker-u3-l3', '**35.0%**', f'{hit2(9) * 100:.1f}%', '35.0%'),
        ('poker-u3-l4', '**25%**', pct(50 / 200), '25%'),
        ('poker-u3-l4', '| 1/3 pot | 20% |', pct((1 / 3) / (1 + 2 / 3)), '20%'),
        ('poker-u3-l4', '| 1/2 pot | 25% |', pct(0.5 / 2), '25%'),
        ('poker-u3-l4', '| 2/3 pot | 28.6% |', pct((2 / 3) / (1 + 4 / 3)), '28.6%'),
        ('poker-u3-l4', '| Full pot | 33.3% |', pct(1 / 3), '33.3%'),
        ('poker-u3-l5', 'about 19.6% exact', pct(9 / 46), '19.6%'),
        ('poker-u3-l5', '60 / 180 = 33.3%', pct(60 / 180), '33.3%'),
        ('poker-u3-l5', '15 / 90 = 16.7%', pct(15 / 90), '16.7%'),
        ('poker-u4-l2', '**+$10**', money(0.30 * 150 - 0.70 * 50), '+$10'),
        ('poker-u4-l3', 'Bet half pot: break even at 33% folds', round(0.5 / 1.5 * 100), 33),
        ('poker-u4-l3', 'Bet full pot: 50%', pct(1 / 2), '50%'),
        ('poker-u4-l3', 'Bet a third of the pot: 25%', pct((1 / 3) / (4 / 3)), '25%'),
        ('poker-u4-l4', 'A-K alone has 12 combos', 3 * 4, 12),
        ('poker-u4-l4', '(9 sets)', 3 * comb(3, 2), 9),
        ('poker-u5-l2', 'about two-thirds of the time', round(miss, 2), 0.68),
        ('poker-u6-l4', 'roughly ±16-20 bb/100', (round(2 * 80 / 10), round(2 * 100 / 10)), (16, 20)),
        ('poker-u6-l4', 'around ±5-6 bb/100', (int(2 * 80 / 1000 ** 0.5), int(2 * 100 / 1000 ** 0.5)), (5, 6)),
    ]


def exact_equity(h1, h2, board):
    h1, h2, board = h1.split(), h2.split(), board.split()
    rest = [c for c in FULL if c not in h1 + h2 + board]
    w = t = n = 0
    for x in combinations(rest, 5 - len(board)):
        bd = board + list(x); a, b = score(bd, h1), score(bd, h2)
        n += 1; w += a < b; t += a == b
    return 100 * (w + t / 2) / n


def main():
    path = path_for('poker')
    samples = int(sys.argv[sys.argv.index('--samples') + 1]) if '--samples' in sys.argv else 20000
    r = Report('poker')
    doc, puzzles, stats = check_schema(path, 'poker', r, allow_puzzles=False)
    rng = random.Random(2026)
    n_exact = n_mc = n_concept = 0
    for u in doc['units']:
        for l in u['lessons']:
            for q in l['quiz']:
                ans = q['choices'][q['answer']]
                res = compute(q['prompt'])
                if res is None:
                    n_concept += 1; continue
                kind, val = res
                if kind == 'exact':
                    r.ok(ans == val, f'{l["id"]}: "{q["prompt"][:60]}" marked {ans}, computed {val}', 'recompute')
                    r.ok(val not in [c for i, c in enumerate(q['choices']) if i != q['answer']], f'{l["id"]}: computed value also a distractor', 'recompute')
                    n_exact += 1
                else:
                    eq = mc_equity(*val, samples, rng)
                    nums = [int(re.match(r'About (\d+)%$', c).group(1)) for c in q['choices']]
                    r.ok(abs(nums[q['answer']] - eq) <= 2, f'{l["id"]}: preflop marked {ans}, simulated {eq:.1f}%', 'equity')
                    r.ok(all(abs(x - eq) >= 6 for i, x in enumerate(nums) if i != q['answer']), f'{l["id"]}: a distractor is within 6 points of {eq:.1f}%', 'equity')
                    n_mc += 1
    bodies = {l['id']: l['body'] for u in doc['units'] for l in u['lessons']}
    facts = body_facts()
    for lid, text, got, exp in facts:
        r.ok(text in bodies.get(lid, ''), f'{lid}: body does not contain "{text}"', 'prose')
        r.ok(got == exp, f'{lid}: "{text}" recomputes to {got}', 'prose')
    # equity claims in poker-u4-l1, by exact enumeration of all flop-to-river runouts
    fd = exact_equity('9h 8h', 'Kc Qd', 'Kh 4h 2c'); op = exact_equity('Qs Qd', '7c 7h', '7s 4d 2c')
    r.ok('roughly 37% against one pair' in bodies['poker-u4-l1'] and abs(fd - 37) < 1, f'flush draw vs pair {fd:.1f}%', 'prose')
    r.ok('around 9% for the overpair' in bodies['poker-u4-l1'] and abs(op - 9) < 1, f'overpair vs set {op:.1f}%', 'prose')
    return r.finish(f'{stats}; {n_exact} numeric answers recomputed exactly, {n_mc} preflop equities re-simulated '
                    f'({samples} deals), {len(facts) + 2} body figures recomputed, {n_concept} conceptual questions schema-only')


if __name__ == '__main__':
    sys.exit(main())
