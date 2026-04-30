# Iron — Product Requirements Document

**Version:** 1.0
**Date:** 2026-04-30
**Owner:** Doug
**Status:** Pre-alpha

---

## 1. Vision

Iron is the open-source workout tracker for the **hybrid lifter** — someone who lifts seriously and conditions seriously, and refuses to bounce between two apps to do it.

Hevy, Strong, and Liftin' are lifting-only. Strava and Apple Fitness are cardio-only. The hybrid lifter is underserved despite being a fast-growing audience (CrossFit, Hyrox, tactical, military, hybrid athletes).

Iron is **MIT-licensed**, **iCloud-synced**, **HealthKit-native**, and **free at the full-app level**. Pro features (AI form check, adaptive programming, advanced analytics) are server-side and gated by subscription.

## 2. Target Audience

**Primary:** Lifters 25–45 who also run, row, or do HIIT 2–4× per week. Care about data ownership, suspicious of subscription-first SaaS, comfortable on iOS.

**Secondary:** Coaches who want to share programs with clients, track multiple lifters, and run their business without paying $30/mo for TrueCoach.

**Anti-persona:** Casual gym-goer who just wants step counts. Powerlifter who only cares about 1RM. Apple Fitness+ users who want guided classes.

## 3. Positioning

> **"The open-source Hevy."**

- vs Hevy: Iron is open source. You own your data. iCloud sync is free.
- vs Strong: Iron is modern (SwiftUI, SwiftData, watchOS native). Strong is a 2014 codebase.
- vs Liftin': Iron has a real free tier — full app, not a 7-day trial.
- vs Apple Fitness: Iron is hypertrophy-aware, with programs, RPE, e1RM, MEV/MAV/MRV.

## 4. Goals & Non-Goals

### Goals
- Ship MVP to TestFlight within 30 days
- Public GitHub launch with first 100 stars in 60 days
- 1,000 free-tier installs within 90 days
- 50 paying Pro subscribers within 120 days ($400 MRR)
- Become the default recommendation in r/Fitness and r/weightroom for "open-source workout tracker"

### Non-Goals (v1)
- Android (kills the watchOS story; revisit if iOS demand validates)
- Social feed / following / likes (Hevy's wedge, not ours)
- Nutrition tracking (Cronometer/MyFitnessPal own this)
- Pure cardio focus (Strava owns this)
- Web app (mobile-first; web export is enough)

## 5. Free Tier (MVP)

### 5.1 Lifting Core
- **Exercise library** — 200+ exercises seeded, MIT-licensed, community PRs welcome
- **Programs** — built-in (5/3/1, PPL, Starting Strength, GZCLP), import/export JSON, custom builder
- **Logging** — set/rep/weight/RPE, drop sets, supersets, AMRAP, rest-pause
- **Plate calculator** — barbell/dumbbell, configurable plate sets (lb/kg)
- **Rest timer** — auto-start on set complete, customizable, Watch haptics
- **Notes** — per-set, per-exercise, per-workout

### 5.2 Conditioning Module
- **HIIT/intervals** — round/work/rest builder, audio cues, Watch sync
- **Runs/rows/cycles** — pull from HealthKit, no GPS rebuild
- **HR zones** — display during conditioning, Watch + iPhone

### 5.3 History + PRs
- **Auto-detect PRs** — 1RM, e1RM (Epley), 3RM, 5RM, volume, AMRAP reps
- **Trends** — volume per muscle group, frequency, intensity over time
- **Calendar view** — at-a-glance month/year history
- **Search** — by exercise, muscle, date

### 5.4 Apple Watch Companion
- Log sets from wrist
- Rest timer with haptics
- Heart rate stream during conditioning
- Standalone (no iPhone needed mid-set)

### 5.5 HealthKit Integration
- **Read** — body weight, heart rate, runs, cycles, swims
- **Write** — strength training, HIIT, custom workouts (so they appear in Apple Health)

### 5.6 Sync + Export
- **iCloud sync** — free, user's CloudKit container, automatic
- **JSON export** — full data dump, machine-readable
- **CSV export** — per-exercise, per-workout, for Excel/Sheets

## 6. Pro Tier ($7.99/mo or $59/yr)

### 6.1 AI Form Check
- Upload video (lift), get AI critique
- Squat depth, bar path, knee tracking, lockout
- Powered by Gemini Flash (multimodal, cheap)
- Stored in user's iCloud, processed server-side via Convex action

### 6.2 AI Programming
- Adaptive program generation (Claude Haiku)
- Deload suggestions based on fatigue signals
- Progression schemes auto-tuned to performance

### 6.3 Advanced Analytics
- **Fatigue tracking** — acute:chronic workload ratio (ACWR)
- **Volume landmarks** — MEV/MAV/MRV per muscle group, recommended weekly sets
- **Readiness score** — combines HRV, sleep, soreness self-report
- **Mesocycle planner** — block periodization, autoregulation

### 6.4 Health Insights
- Correlate sleep/HRV/nutrition with PRs
- "Your bench PRs hit on days when you sleep 7.5+ hours"
- Powered by Apple Health data, on-device + server analysis

### 6.5 Coach Mode
- Share programs with clients
- Track multiple lifters from one account
- Comment on workouts, send adjustments
- Replaces $30/mo TrueCoach for solo coaches

### 6.6 Premium Export
- PDF program summaries (for printing, gym wall)
- Notion export (formatted database)
- Markdown export (for Obsidian, etc.)

## 7. Technical Architecture

### 7.1 Stack
- **App** — SwiftUI (iOS 18+), SwiftData (persistence), Swift 6 concurrency
- **Watch** — watchOS 11+, native SwiftUI app, WatchConnectivity for sync
- **HealthKit** — native HKHealthStore, async/await wrappers
- **Sync** — CloudKit for free tier (built into SwiftData)
- **Backend (Pro only)** — Convex (TypeScript), invoked via REST from app
- **AI** — Claude Haiku (text/programming), Gemini Flash (vision/form check)
- **Auth** — Sign in with Apple (free tier needs nothing; Pro requires account)
- **Payments** — StoreKit 2, on-device receipts, server-side validation via Convex

### 7.2 Why Native
- Watch latency on React Native is unacceptable for set logging
- HealthKit Swift API is leagues better than the JS bridges
- SwiftData + CloudKit gives us free sync — no backend needed for free tier
- AppIntents + Shortcuts integration is native-only in practice

### 7.3 Data Model
See [`schema.md`](schema.md) for the full SwiftData schema.

### 7.4 Privacy
- Free tier: 100% on-device + iCloud, no servers, no analytics, no telemetry
- Pro tier: only Pro feature payloads (form check video, AI prompts) leave device
- No tracking, no third-party analytics, no ads — ever

## 8. Monetization

| Tier | Price | What you get |
|---|---|---|
| Free | $0 | Full app, iCloud sync, HealthKit, Watch, exports |
| Pro Monthly | $7.99/mo | + AI form check, AI programming, advanced analytics, coach mode |
| Pro Annual | $59/yr | Same as monthly, ~38% off |

**Why this works:**
- Free tier is genuinely useful → trust → habit
- Pro features cost money to run (AI inference) → fair to charge
- Annual price ($59) is below Hevy Pro ($89/yr) → competitive wedge
- Open source means no platform risk; users know we can't rug-pull free tier

## 9. Open Source Strategy

- **License:** MIT (permissive — coaches/devs can build on top)
- **Repo:** [github.com/highimpact-dev/iron](https://github.com/highimpact-dev/iron)
- **Contributions welcome:** exercise library, programs, translations, bug fixes
- **Pro features stay private** — AI prompts, server logic, Convex schemas live in a separate private repo
- **Public roadmap** — GitHub Projects, milestones, public discussions
- **Discord** — community space for users + contributors

## 10. Risks

| Risk | Mitigation |
|---|---|
| Apple changes HealthKit access | Native APIs are stable; Apple unlikely to break |
| Hevy adds open-source clone | They won't — their moat is closed |
| Pro AI costs > Pro revenue | Cap usage per tier (e.g. 10 form checks/mo); scale prices to costs |
| Solo dev burnout | Open source = community helps; ship MVP fast, validate before scaling |
| App Store rejection | Sub model is standard; no precedent for rejecting open-source apps |

## 11. Success Metrics (90 days)

- 100 GitHub stars
- 1,000 free-tier installs
- 50 paying Pro subscribers
- 4.5+ App Store rating
- 5+ external contributors

## 12. Timeline

See [`shipping-plan.md`](shipping-plan.md) for week-by-week.

- **Week 1** (Apr 30 – May 6) — SwiftData schema, exercise library seed, basic logging UI
- **Week 2** (May 7 – May 13) — Workout flow, rest timer, PR detection, HealthKit write
- **Week 3** (May 14 – May 20) — Watch app (set logging from wrist)
- **Week 4** (May 21 – May 27) — TestFlight beta, public GitHub launch
- **Week 5+** — Pro feature buildout, marketing, community
