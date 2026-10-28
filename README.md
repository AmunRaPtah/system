# System

A native SwiftUI iOS 17 app modelled on the System from Solo Leveling. It is a
personal quest board for body, mind, social life and sovereignty: daily, weekly
and monthly quests, nine stats, levels and E-to-S ranks with benchmark trials,
penalty quests for missed days, a 12-week training programme with a workout
logger, perception drills, and chess/go/poker lessons with puzzles. Data stays
on the device (SwiftData). There is no account and no network use.

## Build

The project is generated with XcodeGen from `ios/project.yml`.

    brew install xcodegen
    cd ios && xcodegen generate
    open System.xcodeproj

CI (`.github/workflows/build-ipa.yml`, "Build IPA") builds an unsigned
Release `.ipa` on every push to `main` touching `ios/`. It is uploaded as the
`System-ipa` artifact and to the `latest` release. Sideload with AltStore or
SideStore.

## Content

Quest, lesson and training content is JSON read at runtime from
`ios/System/Resources/Content/` (a folder reference, copied as `Content/` in
the app bundle). Every file is optional: a missing or malformed file gives an
empty list, and the app still runs. `training.json` is committed. Challenges and
lessons (`challenges.json`, `lessons-{chess,go,poker}.json`) are authored
separately and are not in the repo. See [CONTENT_SCHEMA.md](CONTENT_SCHEMA.md)
for the format.
