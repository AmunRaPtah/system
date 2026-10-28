"""Schema checks shared by the lessons-*.json validators (see ../CONTENT_SCHEMA.md).

Checks: exact key sets (camelCase, no extras, no nulls), types, kebab-case ids
(Lichess puzzle ids keep their case: lichess-<PuzzleId>), ids unique per file,
unit order 1..n, difficulty 1-5 and non-decreasing, body 80-300 words,
2-4 questions, 4 distinct choices, answer index 0-3, explain 1-2 sentences,
puzzle fields present and typed.
"""
import json, re, sys
from collections import Counter

KEBAB = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
LICHESS = re.compile(r'^lichess-[A-Za-z0-9]{5}$')
TOP = {'version', 'game', 'units'}
UNIT = {'id', 'title', 'order', 'difficulty', 'lessons'}
LESSON = {'id', 'title', 'body', 'quiz'}
QUESTION = {'prompt', 'choices', 'answer', 'explain'}
PUZZLE = {'id', 'position', 'toMove', 'solution', 'goal', 'rating'}


class Report:
    def __init__(self, name):
        self.name, self.errors, self.checks = name, [], Counter()

    def ok(self, cond, msg, kind='check'):
        self.checks[kind] += 1
        if not cond:
            self.errors.append(msg)
        return cond

    def finish(self, summary):
        for e in self.errors:
            print('FAIL', e)
        total = sum(self.checks.values())
        status = 'PASS' if not self.errors else f'FAILED ({len(self.errors)} errors)'
        print(f'{self.name}: {status} - {total} checks; {summary}')
        return 0 if not self.errors else 1


def words(body):
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'’.,%/×+-]*", body))


def sentences(text):
    t = re.sub(r'\b(e\.g|i\.e|vs|etc)\.', r'\1', text)
    t = re.sub(r'(\d)\.(\d)', r'\1\2', t)
    return len([s for s in re.split(r'(?<=[.!?])\s+', t.strip()) if s])


def no_nulls(x, path, r):
    if isinstance(x, dict):
        for k, v in x.items():
            no_nulls(v, f'{path}.{k}', r)
    elif isinstance(x, list):
        for i, v in enumerate(x):
            no_nulls(v, f'{path}[{i}]', r)
    else:
        r.ok(x is not None, f'{path}: null value', 'nulls')


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def check_schema(path, game, r, allow_puzzles):
    doc = json.load(open(path, encoding='utf-8'))
    no_nulls(doc, game, r)
    r.ok(set(doc) == TOP, f'top-level keys {sorted(doc)}', 'keys')
    r.ok(doc.get('version') == 1, 'version must be 1')
    r.ok(doc.get('game') == game, f'game must be {game}')
    ids = []
    prev_diff = 0
    puzzles = []
    answers = Counter()
    for ui, u in enumerate(doc['units'], 1):
        up = u.get('id')
        r.ok(set(u) == UNIT, f'{up}: unit keys {sorted(u)}', 'keys')
        r.ok(isinstance(up, str) and KEBAB.match(up) and up.startswith(game + '-'), f'{up}: bad unit id', 'ids')
        ids.append(up)
        r.ok(isinstance(u['title'], str) and u['title'].strip(), f'{up}: empty title')
        r.ok(u['order'] == ui and is_int(u['order']), f'{up}: order {u["order"]} != {ui}')
        d = u['difficulty']
        r.ok(is_int(d) and 1 <= d <= 5, f'{up}: difficulty {d} not 1-5')
        r.ok(d >= prev_diff, f'{up}: difficulty decreases ({prev_diff} -> {d})')
        prev_diff = d
        r.ok(isinstance(u['lessons'], list) and u['lessons'], f'{up}: no lessons')
        for l in u['lessons']:
            lp = l.get('id')
            extra = {'puzzles'} if allow_puzzles else set()
            r.ok(LESSON <= set(l) <= LESSON | extra, f'{lp}: lesson keys {sorted(l)}', 'keys')
            r.ok(isinstance(lp, str) and KEBAB.match(lp) and lp.startswith(up.rsplit('-', 1)[0]), f'{lp}: bad lesson id', 'ids')
            ids.append(lp)
            r.ok(isinstance(l['title'], str) and l['title'].strip(), f'{lp}: empty title')
            wc = words(l['body'])
            r.ok(isinstance(l['body'], str) and 80 <= wc <= 300, f'{lp}: body has {wc} words (80-300)', 'body')
            q = l['quiz']
            r.ok(isinstance(q, list) and 2 <= len(q) <= 4, f'{lp}: {len(q)} questions (2-4)', 'quiz')
            prompts = set()
            for qi, x in enumerate(q):
                qp = f'{lp} q{qi + 1}'
                r.ok(set(x) == QUESTION, f'{qp}: keys {sorted(x)}', 'keys')
                r.ok(isinstance(x['prompt'], str) and x['prompt'].strip() and x['prompt'] not in prompts, f'{qp}: empty or duplicate prompt', 'quiz')
                prompts.add(x['prompt'])
                ch = x['choices']
                r.ok(isinstance(ch, list) and len(ch) == 4 and all(isinstance(c, str) and c.strip() for c in ch)
                     and len(set(ch)) == 4, f'{qp}: need 4 distinct non-empty choices', 'quiz')
                r.ok(is_int(x['answer']) and 0 <= x['answer'] < len(ch), f'{qp}: answer {x["answer"]} out of range', 'answer')
                answers[x['answer']] += 1
                ns = sentences(x['explain'])
                r.ok(isinstance(x['explain'], str) and 1 <= ns <= 2, f'{qp}: explain has {ns} sentences (1-2)', 'explain')
            for p in l.get('puzzles', []):
                pp = p.get('id')
                r.ok(set(p) == PUZZLE, f'{lp}/{pp}: puzzle keys {sorted(p)}', 'keys')
                r.ok(isinstance(pp, str) and (KEBAB.match(pp) or LICHESS.match(pp)), f'{pp}: bad puzzle id', 'ids')
                ids.append(pp)
                r.ok(p['toMove'] in ('w', 'b'), f'{pp}: toMove')
                r.ok(isinstance(p['position'], str) and isinstance(p['goal'], str) and p['goal'], f'{pp}: position/goal type')
                r.ok(isinstance(p['solution'], list) and p['solution'] and all(isinstance(m, str) for m in p['solution']), f'{pp}: solution')
                r.ok(is_int(p['rating']) and p['rating'] > 0, f'{pp}: rating')
                puzzles.append((lp, p))
            if allow_puzzles and 'puzzles' in l:
                r.ok(len(l['puzzles']) >= 1, f'{lp}: empty puzzles list')
    dup = [k for k, v in Counter(ids).items() if v > 1]
    r.ok(not dup, f'duplicate ids {dup}', 'ids')
    lessons = [l for u in doc['units'] for l in u['lessons']]
    stats = dict(units=len(doc['units']), lessons=len(lessons),
                 questions=sum(len(l['quiz']) for l in lessons), puzzles=len(puzzles),
                 answerSpread=dict(sorted(answers.items())))
    return doc, puzzles, stats


def path_for(game):
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    return sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else os.path.join(here, '..', 'ios', 'System', 'Resources', 'Content', f'lessons-{game}.json')
