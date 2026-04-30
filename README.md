# Iron

> The open-source Hevy. A hybrid lifting + conditioning workout tracker for serious lifters who also condition.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20watchOS-blue)](https://github.com/highimpact-dev/iron)

## Why Iron

Hevy owns lifting tracking. Strong is dated. Liftin' is paid-only. None handle the lifter who also runs, rows, or does HIIT — and none let you own your data.

Iron does both. Open source. MIT. Free tier is the full app.

## Features

### Free (forever, no nags, no ads)
- Lifting core: programs (5/3/1, PPL, custom), set/rep/RPE/weight, plate calculator, rest timer
- Conditioning module: HIIT, intervals, runs (HealthKit pull, no GPS rebuild)
- History + PRs: auto-detect 1RM, e1RM, volume PRs
- Apple Watch companion: log sets from wrist, heart rate during conditioning
- HealthKit two-way: read runs/HR, write workouts back
- iCloud sync via your CloudKit container
- Full export (JSON/CSV)

### Pro ($7.99/mo or $59/yr)
- AI form check: video upload → critique (squat depth, bar path, etc.)
- AI programming: adaptive program generation, deload suggestions
- Advanced analytics: fatigue tracking, volume landmarks (MEV/MAV/MRV per muscle), readiness score
- Apple Health deep insights: correlate sleep/HRV/nutrition with PRs
- Coach mode: share programs, track lifters
- Export to PDF/Notion

## Stack

- **iOS native** — SwiftUI + SwiftData + HealthKit + WatchKit
- **Sync** — CloudKit (free tier), Convex (Pro AI features only)
- **AI** — Claude Haiku (programming), Gemini Flash (form check video)

## Status

Pre-alpha. Targeting TestFlight beta within 30 days of repo init (2026-04-30).

See [`spec/20260430-iron-workout-app/`](spec/20260430-iron-workout-app/) for the PRD, schema, and shipping plan.

## Contributing

Open to PRs for:
- Exercise library entries
- Program templates (push/pull/legs, 5/3/1, Starting Strength, etc.)
- Translations
- Bug fixes

Pro features (AI form check, adaptive programming, advanced analytics) live server-side and are not in this repo.

## License

[MIT](LICENSE)
