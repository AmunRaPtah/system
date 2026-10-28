"""Validate lessons-go.json.

Usage: python validate_go.py [lessons-go.json]   (pure Python, no dependencies)

The 9x9 rules engine is embedded below (liberties, captures, suicide, simple
ko, Benson unconditional life, a ladder/net capture reader and a local
life-and-death search). Besides the shared schema checks, every puzzle is
replayed from its position string and its goal is re-derived:
  - all moves legal (occupied/suicide/ko), alternating from toMove
  - "Capture N stones": the first move captures N and is the only move that does;
    "(ko)" puzzles also check the immediate recapture is illegal
  - "Save your stone": the only move after which the chain in atari has 2+
    liberties and cannot be laddered
  - ladder/net goals: the only first move that captures by force; for longer
    lines every solver move keeps the target in atari and is the unique winner
  - "Make two eyes": the only move giving Benson life, and the group dies if
    the opponent moves first
  - "Kill: stop two eyes": the only killing point, and the group lives if it
    moves first
Quiz facts that can be computed (scoring arithmetic, liberty and capture
counts, square-four dead / straight-four alive) are recomputed too.
"""
COLS = "abcdefghj"
N = 9

def parse_pos(s):
    rows = s.split("/")
    assert len(rows) == N and all(len(r) == N for r in rows), "bad position string"
    g = {}
    for i, r in enumerate(rows):
        y = N - 1 - i  # row 9 first
        for x, ch in enumerate(r):
            assert ch in ".bw", "bad char " + ch
            if ch != ".":
                g[(x, y)] = ch
    return g

def to_str(g):
    return "/".join("".join(g.get((x, y), ".") for x in range(N)) for y in range(N - 1, -1, -1))

def coord(c):
    assert len(c) == 2 and c[0] in COLS and c[1] in "123456789", "bad coord " + c
    return (COLS.index(c[0]), int(c[1]) - 1)

def name(p):
    return COLS[p[0]] + str(p[1] + 1)

def nbrs(p):
    x, y = p
    for q in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
        if 0 <= q[0] < N and 0 <= q[1] < N:
            yield q

def opp(c):
    return "w" if c == "b" else "b"

def group(g, p):
    c = g[p]; st = [p]; seen = {p}; libs = set()
    while st:
        q = st.pop()
        for r in nbrs(q):
            v = g.get(r)
            if v is None:
                libs.add(r)
            elif v == c and r not in seen:
                seen.add(r); st.append(r)
    return seen, libs

class Illegal(Exception):
    pass

def play(g, color, p, ko_prev=None):
    """Return (new_board, captured_points). ko_prev = board before opponent's last move."""
    if p in g:
        raise Illegal("occupied " + name(p))
    h = dict(g); h[p] = color
    captured = set()
    for r in nbrs(p):
        if h.get(r) == opp(color):
            s, l = group(h, r)
            if not l:
                captured |= s
    for q in captured:
        del h[q]
    s, l = group(h, p)
    if not l:
        raise Illegal("suicide " + name(p))
    if ko_prev is not None and h == ko_prev:
        raise Illegal("ko " + name(p))
    return h, captured

def legal_moves(g, color, ko_prev=None):
    out = []
    for x in range(N):
        for y in range(N):
            p = (x, y)
            if p in g: continue
            try:
                play(g, color, p, ko_prev); out.append(p)
            except Illegal:
                pass
    return out

def run_line(g, first, moves):
    """Play a line alternating from `first`. Returns list of (board, captured) after each move."""
    hist = []; prev = None; cur = g; c = first
    for m in moves:
        nb, cap = play(cur, c, coord(m), prev)
        hist.append((nb, cap, c)); prev, cur = cur, nb; c = opp(c)
    return hist

def benson_alive(g, color):
    """Benson's algorithm: set of points of `color` that are unconditionally alive."""
    pts = [(x, y) for x in range(N) for y in range(N)]
    # chains
    chains = {}; cid = {}
    for p in pts:
        if g.get(p) == color and p not in cid:
            s, l = group(g, p); k = len(chains); chains[k] = (s, l)
            for q in s: cid[q] = k
    # regions: maximal connected sets of points not of `color`
    regions = []; rid = {}
    for p in pts:
        if g.get(p) != color and p not in rid:
            st = [p]; s = {p}; rid[p] = len(regions)
            while st:
                q = st.pop()
                for r in nbrs(q):
                    if g.get(r) != color and r not in s:
                        s.add(r); rid[r] = len(regions); st.append(r)
            regions.append(s)
    def vital(reg, k):
        s, l = chains[k]
        empties = [q for q in reg if q not in g]
        return all(q in l for q in empties) and len(empties) > 0
    def enclosing(reg):
        ks = set()
        for q in reg:
            for r in nbrs(q):
                if r in cid: ks.add(cid[r])
        return ks
    C = set(chains); R = set(range(len(regions)))
    changed = True
    while changed:
        changed = False
        for k in list(C):
            nv = sum(1 for ri in R if vital(regions[ri], k) and enclosing(regions[ri]) <= C)
            if nv < 2:
                C.discard(k); changed = True
        for ri in list(R):
            if not enclosing(regions[ri]) <= C:
                R.discard(ri); changed = True
    alive = set()
    for k in C: alive |= chains[k][0]
    return alive

# ---------------- tactical readers ----------------
def _key(g):
    return tuple(sorted(g.items()))

def capture_reader(g, target, to_move, attacker, prev=None, depth=40, maxlibs=2):
    """Ladder-style reader. Returns (captured: bool, principal line as list of points).
    Attacker may play only on target liberties once the target has <= 2 liberties;
    defender may extend on a liberty or capture an adjacent attacker chain in atari."""
    if target not in g:
        return True, []
    s, libs = group(g, target)
    defender = g[target]
    if depth <= 0:
        return False, []
    if to_move == attacker:
        if len(libs) == 1:
            p = next(iter(libs))
            try:
                play(g, attacker, p, prev)
                return True, [p]
            except Illegal:
                return False, []
        if len(libs) > maxlibs:
            return False, []
        for p in sorted(libs):
            try:
                h, _ = play(g, attacker, p, prev)
            except Illegal:
                continue
            # don't allow self-atari that defender simply captures
            ok, line = capture_reader(h, target, defender, attacker, g, depth - 1, maxlibs)
            if ok:
                return True, [p] + line
        return False, []
    else:
        cands = set(libs)
        for q in s:
            for r in nbrs(q):
                if g.get(r) == attacker:
                    s2, l2 = group(g, r)
                    if len(l2) == 1:
                        cands |= l2
        best = None
        any_legal = False
        for p in sorted(cands):
            try:
                h, _ = play(g, defender, p, prev)
            except Illegal:
                continue
            any_legal = True
            if target not in h:
                continue
            ok, line = capture_reader(h, target, attacker, attacker, g, depth - 1, maxlibs)
            if not ok:
                return False, []
            if best is None or len(line) > len(best[1]):
                best = (p, line)
        if not any_legal or best is None:
            # defender has no useful move: attacker captures by filling remaining libs
            return capture_reader(g, target, attacker, attacker, None, depth - 1, maxlibs)
        return True, [best[0]] + best[1]

def life_search(g, region, defender, to_move, prev=None, depth=10, passes=0):
    """Local life-and-death search restricted to `region` points (+pass for defender).
    Returns 'live' if defender reaches Benson life, 'dead' if all defender stones in region's
    surroundings are captured (none of defender's stones adjacent to region remain), else 'open'."""
    attacker = opp(defender)
    alive = benson_alive(g, defender)
    dstones = [p for p, c in g.items() if c == defender]
    if dstones and len(alive) == len(dstones):
        return "live"
    if not dstones:
        return "dead"
    if depth == 0:
        return "open"
    results = []
    moves = [p for p in region if p not in g]
    for p in moves:
        try:
            h, _ = play(g, to_move, p, prev)
        except Illegal:
            continue
        results.append(life_search(h, region, defender, opp(to_move), g, depth - 1))
    if to_move == defender:
        results.append(life_search(g, region, defender, attacker, None, depth - 1))  # pass
        if "live" in results: return "live"
        if "open" in results: return "open"
        return "dead"
    else:
        if "dead" in results: return "dead"
        if "open" in results or not results: return "open"
        return "live"


# ===================== validator =====================
import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_common import Report, check_schema, path_for


def legal_all(g, c, prev=None):
    return legal_moves(g, c, prev)


def enclosed_region(g, p, owner):
    """Empty points connected to p whose stone neighbours are all `owner`."""
    seen = {p}; st = [p]; ok = True
    while st:
        q = st.pop()
        for r in nbrs(q):
            v = g.get(r)
            if v is None and r not in seen:
                seen.add(r); st.append(r)
            elif v is not None and v != owner:
                ok = False
    return sorted(seen) if ok else None


def check_puzzle(p, r):
    pid = p['id']
    try:
        g = parse_pos(p['position'])
    except AssertionError as e:
        return r.ok(False, f'{pid}: {e}', 'position')
    c = p['toMove']; o = opp(c); goal = p['goal']
    try:
        hist = run_line(g, c, p['solution'])
    except (Illegal, AssertionError) as e:
        return r.ok(False, f'{pid}: illegal solution ({e})', 'legal')
    r.ok(True, '', 'legal')
    r.ok(all(h[2] == (c if i % 2 == 0 else o) for i, h in enumerate(hist)), f'{pid}: moves do not alternate from toMove', 'alternate')
    r.ok(len(p['solution']) % 2 == 1, f'{pid}: solution must end on solver move', 'alternate')
    first = coord(p['solution'][0])
    m = re.match(r'Capture (\d+) stones?( \(ko\))?$', goal)
    if m:
        n = int(m.group(1))
        wins = [q for q in legal_all(g, c) if len(play(g, c, q)[1]) >= n]
        r.ok(wins == [first], f'{pid}: capturing moves {[name(q) for q in wins]}', 'capture-unique')
        r.ok(len(hist[0][1]) == n, f'{pid}: captures {len(hist[0][1])}, goal says {n}', 'capture')
        if m.group(2):
            h, cap = hist[0][0], hist[0][1]
            (q,) = cap
            try:
                play(h, o, q, g); legal_back = True
            except Illegal:
                legal_back = False
            r.ok(not legal_back, f'{pid}: immediate recapture should be illegal (ko)', 'ko')
        return
    if goal == 'Save your stone':
        chains = {frozenset(group(g, q)[0]) for q, v in g.items() if v == c and len(group(g, q)[1]) == 1}
        if not r.ok(len(chains) == 1, f'{pid}: expected exactly one {c} chain in atari', 'escape'):
            return
        tgt = next(iter(next(iter(chains))))
        saves = []
        for q in legal_all(g, c):
            h, _ = play(g, c, q)
            if len(group(h, tgt)[1]) >= 2 and not capture_reader(h, tgt, o, o, g)[0]:
                saves.append(q)
        r.ok(saves == [first], f'{pid}: saving moves {[name(q) for q in saves]}', 'escape-unique')
        return
    if goal in ('Atari toward the edge', 'Capture the stone (net)') or goal.startswith('Run the ladder'):
        net = 'net' in goal
        maxlibs, depth = (3, 9) if net else (2, 40)
        cands = sorted(((len(group(g, q)[1]), q) for q, v in g.items() if v == o))
        tgt = cands[0][1]
        r.ok(len(cands) == 1 or cands[1][0] > cands[0][0], f'{pid}: target chain ambiguous', 'target')
        wins = []
        for q in legal_all(g, c):
            h, _ = play(g, c, q)
            if tgt not in h or capture_reader(h, tgt, o, c, g, depth=depth, maxlibs=maxlibs)[0]:
                wins.append(q)
        r.ok(wins == [first], f'{pid}: winning first moves {[name(q) for q in wins]}', 'chase-unique')
        if not net:
            r.ok(len(group(hist[0][0], tgt)[1]) == 1, f'{pid}: first move is not atari', 'atari')
        # longer ladder lines: every solver move keeps the target in atari and is the unique winner
        prev, cur = None, g
        for i, (h, cap, col) in enumerate(hist):
            mv = coord(p['solution'][i])
            if i % 2 == 0 and i > 0:
                ws = []
                for q in legal_all(cur, c, prev):
                    hh, _ = play(cur, c, q, prev)
                    if tgt not in hh or capture_reader(hh, tgt, o, c, cur, depth=depth, maxlibs=maxlibs)[0]:
                        ws.append(q)
                r.ok(ws == [mv], f'{pid}: ply {i + 1} winning moves {[name(q) for q in ws]}', 'chase-unique')
            if col == o:
                r.ok(tgt in h, f'{pid}: target vanished on defender move', 'chase')
            else:
                r.ok(tgt not in h or len(group(h, tgt)[1]) <= (maxlibs if net else 1), f'{pid}: ply {i + 1} target not in atari', 'atari')
            prev, cur = cur, h
        return
    if goal == 'Make two eyes':
        mine = [q for q, v in g.items() if v == c]
        wins = [q for q in legal_all(g, c) if set(mine) <= benson_alive(play(g, c, q)[0], c)]
        r.ok(wins == [first], f'{pid}: living moves {[name(q) for q in wins]}', 'live-unique')
        region = enclosed_region(g, first, c)
        if r.ok(region is not None, f'{pid}: eye space not enclosed', 'live'):
            r.ok(life_search(g, region, c, o, depth=8) == 'dead', f'{pid}: group is not dead if opponent moves first (move not urgent)', 'live-urgent')
        return
    if goal == 'Kill: stop two eyes':
        d = o
        region = enclosed_region(g, first, d)
        if not r.ok(region is not None, f'{pid}: eye space not enclosed', 'kill'):
            return
        r.ok(life_search(g, region, d, d, depth=8) == 'live', f'{pid}: defender dead even if it moves first', 'kill-urgent')
        wins = []
        for q in region:
            try:
                h, _ = play(g, c, q)
            except Illegal:
                continue
            if life_search(h, region, d, d, g, depth=8) == 'dead':
                wins.append(q)
        r.ok(wins == [first], f'{pid}: killing moves {[name(q) for q in wins]}', 'kill-unique')
        return
    r.ok(False, f'{pid}: unknown goal "{goal}"', 'goal')


def build(black, white):
    g = {}
    for s in black.split(): g[coord(s)] = 'b'
    for s in white.split(): g[coord(s)] = 'w'
    return g


def check_quiz_facts(doc, r):
    """Recompute quiz answers that the engine or arithmetic can decide."""
    qs = {q['prompt']: q['choices'][q['answer']] for u in doc['units'] for l in u['lessons'] for q in l['quiz']}
    n = 0
    for prompt, ans in qs.items():
        m = re.search(r'Black has (\d+) stones and (\d+) surrounded points\. White has (\d+) stones and (\d+) surrounded points, with komi (\d+(?:\.\d+)?)', prompt)
        if m:
            bs = int(m.group(1)) + int(m.group(2)); ws = int(m.group(3)) + int(m.group(4)) + float(m.group(5))
            exp = f"{'Black' if bs > ws else 'White'}, by {abs(bs - ws):g}"
            r.ok(ans == exp, f'counting quiz: expected {exp}, got {ans}', 'quiz-math'); n += 1
        if prompt.startswith('How many liberties does a single stone in the corner have?'):
            r.ok(ans == str(len(group({(0, 0): 'b'}, (0, 0))[1])), 'corner liberties', 'quiz-math'); n += 1
        if prompt.startswith('A white chain of three stones has one liberty left. Black plays there.'):
            r.ok(ans == str(len(play(build('a2 b2 c2', 'a1 b1 c1'), 'b', coord('d1'))[1])),
                 'chain capture count', 'quiz-math'); n += 1
    # eye-shape claims in go-u5-l5, checked by local search on enclosed test shapes
    sq = build('d1 d2 d3 a4 b4 c4 d4', 'c1 c2 a3 b3 c3')
    r.ok(life_search(sq, [coord(x) for x in 'a1 b1 a2 b2'.split()], 'w', 'w', depth=12) == 'dead', 'square four should be dead', 'eye-shape'); n += 1
    st4 = build('a3 b3 c3 d3 e3 f3 f2 f1', 'a2 b2 c2 d2 e2 e1')
    r.ok(life_search(st4, [coord(x) for x in 'a1 b1 c1 d1'.split()], 'w', 'b', depth=8) == 'live', 'straight four should live', 'eye-shape'); n += 1
    return n


def main():
    path = path_for('go')
    r = Report('go')
    doc, puzzles, stats = check_schema(path, 'go', r, allow_puzzles=True)
    for lp, p in puzzles:
        check_puzzle(p, r)
    n = check_quiz_facts(doc, r)
    return r.finish(f'{stats}; {len(puzzles)} puzzles replayed and goal-checked; {n} quiz/prose facts recomputed')


if __name__ == '__main__':
    sys.exit(main())
