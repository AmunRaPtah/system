# System v3: design

Status: agreed 2026-11-17. Supersedes LifeOS (retired 2026-08-20) and Meridian (life.zyco.org, retires at end of Phase 3).

## Why v3 looks like this

| App | What it was | What got used |
|---|---|---|
| LifeOS (Jul-Aug 2026) | 8 domains, 6 pillars, anchors, weekly Reckoning, library | Domains set to 6 once; streak 0; 0 Reckonings; logbooks empty |
| Meridian (Aug-Nov 2026) | 24 instruments, 15 Atlas maps, Patterns, Tensions, The Deep | 0 entries (only the psyche-twin import) |
| System v1/v2 (Oct 28-31) | 9 stats, E-S ranks, penalty quests, chess/go/poker, perception | Built in 4 days, untouched since |

The only self-model still alive is psyche-twin, because it comes to the owner (cron) instead of waiting for a sit-down. Each previous app was more complete and less used. **v3 must work on days the owner gives it nothing.**

Aim, in the owner's words: *healthy, of sound mind and body, and sovereign*, plus ambitions and the logistics of a life, organised in one place.

## Principles

1. **Passive by default.** The box already knows most of it: Zyco ticks and OUTBOX, `/root/application-career` deadlines, git activity, calendar, GrantFinder, HealthKit.
2. **Two gates a day, 30 seconds each.** Morning (energy, intention, accept quests) and evening (done or not, one line). Everything else optional.
3. **Evidence, not self-rating.** Domain levels are computed from what happened. Rank trials (run, push-ups, plank, reaction) stay.
4. **Hard but safe penalties.** Never miss twice; load halved under fatigue.
5. **Self-aware of disuse.** 3 days without a gate: collapse to one-tap mode and send one Telegram nudge.
6. **Digests, not alerts.** Telegram (no APNs on a sideloaded app): morning brief, evening gate reminder, Sunday Reckoning. Individual alerts only for a gate deadline at risk.

## Structure

Sovereignty is the overall rank, not a domain.

| Domain | Covers | Evidence |
|---|---|---|
| Body | training, sleep, health upkeep, appearance | HealthKit, workout log, rank trials |
| Mind | focus, perception, chess/go/poker, practices, state | drill scores, practice log, gates |
| Bonds | friends, family, mentors, network, partner | "tend one person" quests, contact cadence list |
| Ambition | Zyco divisions, research, applications, study | Zyco ticks, git, application tracker, calendar |
| Wealth | runway, income, spend, funding | monthly manual figures, funding wins |
| Ground | visa, documents, admin, housing, legal | deadlines and checklists |

## Ambition

- **Campaign**: a long arc tied to a real goal (e.g. neurocascade funded; METI/Wadhwani; Topologix funding; doctoral path; Germany move; IELTS).
- **Gate**: a dated milestone inside a campaign. Deadlines may be *suggested* from the box (application tracker, Zyco), the owner accepts them.
- **Quest**: a concrete action. **The owner writes every quest.** No model generates quests. Cap of 3 Ambition quests a day.
- **War Room**: every campaign, next gate, days left, moved this week or not. Stale campaigns fade.
- **Choose three**: each Sunday pick at most 3 campaigns to push; the rest are explicitly paused.

## Surfaces (5 tabs)

1. **Today**: status window (rank, level, fatigue, streak), the day's quests, the two gates.
2. **Campaigns**: War Room and campaign -> gate -> quest.
3. **Domains**: six domains with evidence-based levels; Mind holds chess/go/poker and drills, Body the 12-week programme.
4. **Codex**: Sovereign's Education reader with per-essay progress and challenges; **Inner** section ported from Meridian.
5. **Reckoning**: weekly review prefilled from data; the owner confirms or corrects. Quarterly campaign re-score.

## AI

- **Allowed:** drafting the Reckoning summary from box data (`claude -p` on the server). Suggesting gate dates from existing trackers.
- **Not allowed:** writing quests (owner's decision, 2026-11-17); reading or interpreting Inner entries (Meridian's rule stands).

## Inner (Phase 3 scope)

Port the 4 scheduled check-ins (morning, evening, snapshot, weekly) and Tensions. The 20 Meridian event logs come over only on request; instruments stay data, not code.

## Architecture

- **Phone**: this repo, extended. SwiftUI, SwiftData offline-first, HealthKit, widget.
- **Server**: `architect` daemon (not `systemd`). Reads box sources, syncs with the phone, sends Telegram digests. wg0 first; public route later via Caddy mTLS with the Helm CA like Helm/Alfred.
- **Meridian**: instruments ported in Phase 3, then life.zyco.org is shut down.

## Original naming

Keep the genre (status windows, ranks, penalties, titles), drop borrowed Solo Leveling names. Shadow Army -> **Retinue**. Daily Quest (100/100/100/10 km) -> **The Discipline**. Titles renamed to originals.

## Phases (done = used for a week, not built)

| Phase | Scope | Exit test |
|---|---|---|
| 1 | Today + gates, Campaigns with owner-written quests, `architect` deadline feed + Telegram digest, disuse detection, renaming | 7 consecutive days with both gates |
| 2 | Domains with evidence levels, Reckoning | 2 Reckonings completed |
| 3 | Codex: library + Inner port | Meridian retired |
