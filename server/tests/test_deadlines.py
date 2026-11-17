"""Deadline parser: synthetic edge cases plus the real trackers on this box."""
import datetime as dt
from pathlib import Path

import pytest

from architect import deadlines

TODAY = dt.date(2026, 11, 17)
CAREER = Path("/root/application-career")
ZYCO = Path("/root/zyco")


def test_day_month_forms():
    p = deadlines.parse_day_month
    assert p("3 Nov", TODAY) == (dt.date(2026, 11, 3), False)
    assert p("31 Oct 23:59 AoE", TODAY) == (dt.date(2026, 10, 31), False)
    assert p("8-9 Dec", TODAY) == (dt.date(2026, 12, 8), False)
    assert p("8 Jan 2027", TODAY) == (dt.date(2027, 1, 8), False)
    assert p("~15 Jan", TODAY) == (dt.date(2027, 1, 15), True)   # year rolls forward
    assert p("early Dec", TODAY) is None
    assert p("no deadline", TODAY) is None
    assert p("31 Feb", TODAY) is None


def test_synthetic_files(tmp_path):
    career, zyco = tmp_path / "career", tmp_path / "zyco"
    career.mkdir(); zyco.mkdir()
    (career / "README.md").write_text(
        "| Deadline | Application | Type | Status |\n|---|---|---|---|\n"
        "| 1 Dec | [Alpha \\| Lab](http://x) PhD | PhD | Not started |\n"
        "| 2 Dec | Beta School | MSc | SUBMITTED |\n"
        "| 5 Dec | Visa appointment | Admin | booked |\n"
        "| early Jan | Fuzzy Thing | MSc | open |\n")
    (career / "CHECKLIST.md").write_text(
        "## December 2026\n"
        "- [ ] **1 Dec**: **PhD**, Alpha Lab PhD (`alpha/`). Notes here\n"
        "- [x] **3 Dec**: **MSc**, Done Already\n"
        "- [ ] **~9 Dec**: **GF**, Gamma Fund\n"
        "- [ ] **1 Nov**: **PhD**, In The Past\n")
    (zyco / "PORTFOLIO.md").write_text(
        "| Division | Next milestone (date) |\n|---|---|\n"
        "| topologix | 10 interviews (2026-11-30) |\n| bmf | ongoing |\n")
    (zyco / "OPPORTUNITIES.md").write_text(
        "## neurocascade (drugs)\n\n| Opportunity | Deadline | Confidence |\n|---|---|---|\n"
        "| DFG grant | 2026-12-20 | page-confirmed |\n| Vague | rolling | low |\n")
    got = deadlines.suggested_gates(career, zyco, TODAY)
    titles = {g["title"]: g for g in got}
    assert "Alpha Lab PhD" in titles                       # checklist wins, README duplicate merged
    assert not any("Alpha / Lab" in t for t in titles)
    assert "Beta School" not in titles                     # submitted
    assert titles["Visa appointment"]["domain"] == "ground"
    assert titles["Gamma Fund"]["estimated"] is True
    assert "Done Already" not in titles and "In The Past" not in titles
    assert titles["topologix: 10 interviews"]["date"] == "2026-11-30"
    assert titles["neurocascade: DFG grant"]["estimated"] is False
    assert all(set(g) >= {"title", "date", "source", "domain"} for g in got)
    assert [g["date"] for g in got] == sorted(g["date"] for g in got)


needs_real = pytest.mark.skipif(not (CAREER / "CHECKLIST.md").exists(), reason="real trackers absent")


@needs_real
def test_real_trackers():
    got = deadlines.suggested_gates(CAREER, ZYCO, TODAY)
    assert len(got) >= 10
    sources = {g["source"] for g in got}
    assert {"CHECKLIST.md", "PORTFOLIO.md", "OPPORTUNITIES.md"} <= sources
    for g in got:
        d = dt.date.fromisoformat(g["date"])
        assert d >= TODAY
        assert g["domain"] in {"ambition", "ground"}
        assert g["title"] and "**" not in g["title"] and "](" not in g["title"]
    # Spot checks against lines read by hand from the trackers on 2026-11-17.
    by = {(g["date"], g["title"]) for g in got}
    assert ("2026-11-24", "Wellcome Sanger 4-year PhD") in by
    assert ("2026-11-18", "Techstars Boston") in by
    assert any(d == "2026-11-20" and t.startswith("imprint: CLAIMS.md") for d, t in by)
