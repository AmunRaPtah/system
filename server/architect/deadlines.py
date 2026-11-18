"""Suggested gates: dated deadlines parsed from the box's own trackers.

Sources (all read-only):
  /root/application-career/README.md    "Deadline | Application | Type | Status" table
  /root/application-career/CHECKLIST.md "- [ ] **3 Nov**: **PhD**, Title ..." lines under month headings
  /root/zyco/PORTFOLIO.md               "Next milestone (date)" column, ISO date in parentheses
  /root/zyco/OPPORTUNITIES.md           per-division tables with an ISO "Deadline" column

Only concrete future dates are returned. Fuzzy dates ("early Dec", "late Jan", "Mar-Apr",
"no deadline") are skipped. Dates marked "~" in the checklist are kept but flagged
estimated. Items already ticked, submitted, withdrawn or skipped are dropped. Nothing here
creates anything: the phone shows these as suggestions the owner accepts or ignores.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

RECENT_DAYS = 60

MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}

# "3 Nov", "31 Oct 23:59 AoE", "8-9 Dec", "8 Jan 2027", "~15 Jan", "1 Dec 12:00 CET"
DAY_MONTH = re.compile(
    r"^\s*(?P<est>~)?\s*(?P<day>\d{1,2})(?:\s*-\s*\d{1,2})?\s+(?P<mon>[A-Za-z]{3})[a-z]*\.?"
    r"(?:\s+(?P<year>20\d\d))?\b")
ISO = re.compile(r"(20\d\d)-(\d\d)-(\d\d)")
LINK = re.compile(r"\[([^\]]+)\]\([^)]*\)")
DONE_WORDS = re.compile(r"\b(SUBMITTED|WITHDRAWN|SKIPPED|DROPPED|DONE|SENT|REJECTED)\b", re.I)

GROUND_WORDS = re.compile(
    r"\b(visa|passport|residence|legali[sz]|apostille|embassy|consulate|address|housing|"
    r"insurance|tax|permit|registration|anmeldung|bank)\b", re.I)


@dataclass
class Suggestion:
    title: str
    date: str          # YYYY-MM-DD
    source: str        # file name, e.g. "CHECKLIST.md"
    domain: str        # "ambition" | "ground"
    estimated: bool = False
    detail: str = ""
    id: str = field(default="")

    def __post_init__(self) -> None:
        if not self.id:
            h = hashlib.sha1(f"{self.source}|{self.date}|{self.title}".encode()).hexdigest()
            self.id = h[:16]


def clean(text: str) -> str:
    text = LINK.sub(r"\1", text)
    text = text.replace("**", "").replace("`", "")
    text = re.sub(r"\s+", " ", text).strip()
    # A title the source already cut off ("... for young...") keeps a visible ellipsis.
    cut = text.endswith("...") or text.endswith("…")
    text = text.strip(" .,;:-…")
    return text + "…" if cut and text else text


def infer_year(month: int, day: int, today: dt.date, hint: int | None) -> int:
    """Use an explicit year hint. Otherwise this year, unless the date passed more than
    RECENT_DAYS ago, in which case it is next year's ("1 Jun" written in November is June
    next year; "3 Nov" written on 18 Nov is a deadline just missed)."""
    if hint:
        return hint
    try:
        this_year = dt.date(today.year, month, day)
    except ValueError:      # 29 Feb in a non-leap year: let the caller reject it
        return today.year
    return today.year if (today - this_year).days <= RECENT_DAYS else today.year + 1


def parse_day_month(text: str, today: dt.date, year_hint: int | None = None) -> tuple[dt.date, bool] | None:
    m = DAY_MONTH.match(text)
    if not m:
        return None
    mon = MONTHS.get(m.group("mon").lower())
    if not mon:
        return None
    day = int(m.group("day"))
    year = int(m.group("year")) if m.group("year") else infer_year(mon, day, today, year_hint)
    try:
        return dt.date(year, mon, day), bool(m.group("est"))
    except ValueError:
        return None


def domain_for(kind: str, title: str) -> str:
    if kind.strip().lower() == "admin" or GROUND_WORDS.search(title):
        return "ground"
    return "ambition"


def split_row(line: str) -> list[str]:
    """Cells of a markdown table row. A "|" inside link text ([a | b](url)) is not a separator."""
    line = re.sub(r"\[([^\]]*)\]", lambda m: "[" + m.group(1).replace("|", "/") + "]", line)
    line = line.replace("\\|", "/")
    return [c.strip() for c in line.strip().strip("|").split("|")]


def table_rows(lines: list[str], start: int) -> list[list[str]]:
    """Rows of the markdown table whose header is at `start` (separator row skipped)."""
    rows = []
    for line in lines[start + 2:]:
        if not line.startswith("|"):
            break
        rows.append(split_row(line))
    return rows


# ---------------------------------------------------------------- application-career

def parse_career_readme(path: Path, today: dt.date) -> list[Suggestion]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[Suggestion] = []
    for i, line in enumerate(lines):
        if not re.match(r"^\|\s*Deadline\s*\|", line):
            continue
        for cells in table_rows(lines, i):
            if len(cells) < 4:
                continue
            deadline, app, kind, status = cells[0], cells[1], cells[2], cells[3]
            if DONE_WORDS.search(status):
                continue
            parsed = parse_day_month(deadline, today)   # returns None on impossible dates
            if not parsed:
                continue
            date, est = parsed
            title = clean(app)
            out.append(Suggestion(title=title, date=date.isoformat(), source=path.name,
                                  domain=domain_for(kind, title), estimated=est,
                                  detail=clean(f"{kind}. {status}")[:160]))
    return out


CHECK_LINE = re.compile(r"^\s*-\s*\[(?P<mark>[ xX-])\]\s*\*\*(?P<date>[^*]+)\*\*(?P<rest>.*)$")
YEAR_HEADING = re.compile(r"^#{1,6}\s.*?\b(20\d\d)\b")


def parse_checklist(path: Path, today: dt.date, include_ticked: bool = False) -> list[Suggestion]:
    if not path.exists():
        return []
    out: list[Suggestion] = []
    year_hint: int | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            h = YEAR_HEADING.match(line)
            year_hint = int(h.group(1)) if h else None
            continue
        m = CHECK_LINE.match(line)
        if not m or (m.group("mark") != " " and not include_ticked):
            continue
        parsed = parse_day_month(m.group("date"), today, year_hint)
        if not parsed:
            continue
        date, est = parsed
        rest = m.group("rest")
        # "(referees 10 Nov): **PhD**, Title (folder). Notes"
        km = re.search(r"\*\*(?P<kind>[A-Za-z]+)\*\*\s*,?\s*(?P<title>.*)", rest)
        if km:
            kind, title = km.group("kind"), km.group("title")
        else:
            kind, title = "", rest
        title = re.split(r"\s\(`|\.\s(?=[A-Z])", title, maxsplit=1)[0]
        title = clean(re.sub(r"\(`[^)]*`\)", "", title))
        if not title:
            continue
        out.append(Suggestion(title=title[:120], date=date.isoformat(), source=path.name,
                              domain=domain_for(kind, title), estimated=est,
                              detail=kind))
    return out


# ---------------------------------------------------------------- zyco

def parse_portfolio(path: Path, today: dt.date) -> list[Suggestion]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[Suggestion] = []
    for i, line in enumerate(lines):
        if not (line.startswith("|") and "Next milestone" in line):
            continue
        header = split_row(line)
        try:
            col = next(j for j, h in enumerate(header) if h.startswith("Next milestone"))
        except StopIteration:
            continue
        for cells in table_rows(lines, i):
            if len(cells) <= col:
                continue
            iso = ISO.search(cells[col])
            if not iso:
                continue
            try:
                date = dt.date(*map(int, iso.groups()))
            except ValueError:
                continue
            milestone = clean(re.sub(r"\(\s*20\d\d-\d\d-\d\d\s*\)", "", cells[col]))
            out.append(Suggestion(title=f"{cells[0]}: {milestone}"[:120], date=date.isoformat(),
                                  source=path.name, domain="ambition", detail=clean(cells[0])))
    return out


def parse_opportunities(path: Path, today: dt.date) -> list[Suggestion]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[Suggestion] = []
    division = ""
    for i, line in enumerate(lines):
        h = re.match(r"^##\s+([\w-]+)\s+\(", line)
        if h:
            division = h.group(1)
            continue
        if not (line.startswith("|") and "Opportunity" in line and "Deadline" in line):
            continue
        header = split_row(line)
        oc, dc = _col(header, "Opportunity"), _col(header, "Deadline")
        if oc is None or dc is None:
            continue
        cc, divc = _col(header, "Confidence"), _col(header, "Division")
        for cells in table_rows(lines, i):
            if len(cells) <= max(oc, dc):
                continue
            iso = ISO.search(cells[dc])
            if not iso:
                continue
            try:
                date = dt.date(*map(int, iso.groups()))
            except ValueError:
                continue
            div = cells[divc] if divc is not None and len(cells) > divc else division
            conf = cells[cc] if cc is not None and len(cells) > cc else ""
            title = clean(cells[oc])
            out.append(Suggestion(title=f"{div}: {title}"[:120] if div else title[:120],
                                  date=date.isoformat(), source=path.name, domain="ambition",
                                  estimated="page-confirmed" not in conf,
                                  detail=clean(conf)))
    return out


# ---------------------------------------------------------------- merge

def _col(header: list[str], name: str) -> int | None:
    """Index of the first header cell starting with `name` ("Opportunity (link)" counts)."""
    return next((j for j, h in enumerate(header) if h.lower().startswith(name.lower())), None)


def _tokens(title: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", title.lower()) if len(w) >= 4}


def suggested_gates(career_dir: Path, zyco_dir: Path, today: dt.date | None = None) -> list[dict]:
    today = today or dt.date.today()
    checklist = parse_checklist(career_dir / "CHECKLIST.md", today)
    # Ticked items take part in de-duplication only, so a done item's README twin stays hidden.
    every_item = parse_checklist(career_dir / "CHECKLIST.md", today, include_ticked=True)
    readme = parse_career_readme(career_dir / "README.md", today)
    # The checklist is finer grained and carries tick state, so it wins; a README row is
    # kept only if no checklist item on the same date shares a significant word with it.
    merged = list(checklist)
    for r in readme:
        rt = _tokens(r.title)
        if any(c.date == r.date and rt & _tokens(c.title) for c in every_item):
            continue
        merged.append(r)
    merged += parse_portfolio(zyco_dir / "PORTFOLIO.md", today)
    seen: set[tuple[str, str]] = set()
    for s in parse_opportunities(zyco_dir / "OPPORTUNITIES.md", today):
        key = (s.date, s.title)
        if key not in seen:   # the Top-5 table repeats rows from the per-division tables
            seen.add(key)
            merged.append(s)
    future = [s for s in merged if s.date >= today.isoformat()]
    future.sort(key=lambda s: (s.date, s.source, s.title))
    return [asdict(s) for s in future]
