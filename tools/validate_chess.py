"""Validate lessons-chess.json.

Usage: python validate_chess.py [lessons-chess.json] [--stockfish PATH]
Needs python-chess. Besides the shared schema checks, every puzzle is replayed:
  - FEN parses and is a valid position; toMove matches the FEN side to move
  - every solution move is legal in sequence (so moves alternate), odd length
    (the solver makes the last move)
  - "Mate in N" puzzles: solution has 2N-1 plies, ends in checkmate, and at each
    solver turn the given move is the ONLY move that forces mate in the moves
    left (exhaustive search with python-chess, no engine needed)
  - other puzzles: with --stockfish, each solver move must be the engine's
    best move, at least +1.5 pawns, and clearly better than the second-best
    move (gap >= 150cp unless both are winning/losing in the obvious way).
"""
import sys
import chess
import chess.engine
from validate_common import Report, check_schema, path_for


def mates_in1(b):
    out = []
    for m in b.legal_moves:
        b.push(m)
        if b.is_checkmate():
            out.append(m)
        b.pop()
    return out


def forced_mate(b, n):
    if n == 1:
        return bool(mates_in1(b))
    for m in list(b.legal_moves):
        b.push(m)
        if b.is_checkmate():
            b.pop(); return True
        ok = not b.is_game_over() and all(_reply(b, r, n) for r in list(b.legal_moves))
        b.pop()
        if ok:
            return True
    return False


def _reply(b, r, n):
    b.push(r); res = forced_mate(b, n - 1); b.pop(); return res


def mating_moves(b, n):
    res = []
    for m in list(b.legal_moves):
        b.push(m)
        if b.is_checkmate():
            res.append(m)
        elif n > 1 and not b.is_game_over() and all(_reply(b, r, n) for r in list(b.legal_moves)):
            res.append(m)
        b.pop()
    return res


def main():
    path = path_for('chess')
    sf = sys.argv[sys.argv.index('--stockfish') + 1] if '--stockfish' in sys.argv else None
    r = Report('chess')
    doc, puzzles, stats = check_schema(path, 'chess', r, allow_puzzles=True)
    eng = None
    if sf:
        eng = chess.engine.SimpleEngine.popen_uci(sf, timeout=600)
    mate_n = engine_n = 0
    for lp, p in puzzles:
        pid = p['id']
        try:
            b = chess.Board(p['position'])
        except ValueError as e:
            r.ok(False, f'{pid}: bad FEN {e}', 'fen'); continue
        r.ok(b.is_valid(), f'{pid}: invalid position', 'fen')
        r.ok(('w' if b.turn else 'b') == p['toMove'], f'{pid}: toMove mismatch', 'fen')
        sol = p['solution']
        r.ok(len(sol) % 2 == 1, f'{pid}: solution must end on solver move', 'line')
        start = b.copy()
        legal = True
        for u in sol:
            try:
                m = chess.Move.from_uci(u)
            except ValueError:
                legal = False; break
            if m not in b.legal_moves:
                legal = False; break
            b.push(m)
        r.ok(legal, f'{pid}: illegal move {u} in solution', 'legal')
        if not legal:
            continue
        goal = p['goal']
        if goal.startswith('Mate in '):
            n = int(goal.split()[-1])
            r.ok(len(sol) == 2 * n - 1, f'{pid}: {goal} but {len(sol)} plies', 'mate')
            r.ok(b.is_checkmate(), f'{pid}: line does not end in mate', 'mate')
            bb = start.copy()
            for i, u in enumerate(sol):
                m = chess.Move.from_uci(u)
                if i % 2 == 0:
                    w = mating_moves(bb, n - i // 2)
                    r.ok(w == [m], f'{pid}: ply {i + 1} mating moves {[bb.san(x) for x in w]}', 'mate-unique')
                bb.push(m)
            mate_n += 1
        else:
            if eng:
                bb = start.copy()
                for i, u in enumerate(sol):
                    m = chess.Move.from_uci(u)
                    if i % 2 == 0:
                        info = eng.analyse(bb, chess.engine.Limit(depth=14, time=5), multipv=2)
                        best = info[0]['pv'][0]
                        a = info[0]['score'].relative.score(mate_score=100000)
                        gap_ok = True
                        if len(info) > 1:
                            c = info[1]['score'].relative.score(mate_score=100000)
                            gap_ok = a - c >= 150 or (a >= 500 and c <= 300)
                        r.ok(best == m and a >= 150 and gap_ok,
                             f'{pid}: ply {i + 1} {bb.san(m)} engine best {bb.san(best)} score {a}', 'engine')
                    bb.push(m)
                engine_n += 1
    if eng:
        eng.quit()
    extra = f'{mate_n} mate puzzles proved unique by exhaustive search'
    extra += f', {engine_n} tactic puzzles engine-checked' if eng else ', engine check skipped (no --stockfish)'
    return r.finish(f'{stats}; {extra}')


if __name__ == '__main__':
    sys.exit(main())
