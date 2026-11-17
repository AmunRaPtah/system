# System

A native SwiftUI iOS 17 app in the status-window genre. It is a
personal quest board for body, mind, social life and sovereignty: daily, weekly
and monthly quests, nine stats, levels and E-to-S ranks with benchmark trials,
penalty quests for missed days, a 12-week training programme with a workout
logger, perception drills, and chess/go/poker lessons with puzzles. Data stays
on the device (SwiftData). There is no account.

v3 (see `docs/V3-DESIGN.md`) adds a Today tab with a morning and an evening
gate, owner-written quests tagged by domain (Body, Mind, Bonds, Ambition,
Wealth, Ground; at most three Ambition quests a day), and a Campaigns tab:
campaign → dated gate → quest, a War Room and a Sunday "choose three". After
three days without a gate, Today collapses to one tap. The app works fully
offline; if an architect URL and token are set in Settings it also syncs a
snapshot to the owner's server.

## architect server

`server/` is a small FastAPI service bound to the private network
(`10.66.66.1:3380`, bearer token in `~/.architect/token`). It serves
`/suggested-gates` parsed from the owner's trackers, stores `/sync` snapshots in
sqlite under `~/.architect/`, and sends batched Telegram digests from cron
(`architect_digest.py morning|evening|check`), silent until the phone has synced
once. `server/deploy.sh` installs it to `/opt/architect` with a systemd unit.
Tests: `cd server && python3 -m pytest -q`.

## Build

The project is generated with XcodeGen from `ios/project.yml`.

    brew install xcodegen
    cd ios && xcodegen generate
    open System.xcodeproj

CI (`.github/workflows/build-ipa.yml`, "Build IPA") builds an unsigned
Release `.ipa` on every push touching `ios/`, on any branch. It is uploaded as
the `System-ipa` artifact; pushes to `main` also update the `latest` release. Sideload with AltStore or
SideStore.

## Content

Quest, lesson and training content is JSON read at runtime from
`ios/System/Resources/Content/` (a folder reference, copied as `Content/` in
the app bundle). Every file is optional: a missing or malformed file gives an
empty list, and the app still runs. All content is committed: `training.json`,
`challenges.json` and `lessons-{chess,go,poker}.json`. See
[CONTENT_SCHEMA.md](CONTENT_SCHEMA.md) for the format.

Validate before pushing a content change (`tools/`, needs `pip install chess treys`):

    for v in challenges chess go poker; do python3 tools/validate_$v.py || break; done
