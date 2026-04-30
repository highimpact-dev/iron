# Iron — 30-Day Shipping Plan

**Start:** 2026-04-30 (Thursday)
**TestFlight beta:** 2026-05-27 (Wednesday)
**Public GitHub launch:** 2026-05-28 (Thursday)

## Daily Cadence Assumption

4 hours/day of focused work. Adjust if shorter. Buffer days are baked in.

---

## Week 1 (Apr 30 – May 6) — Foundations

**Goal:** App boots, schema is right, can log a single set.

| Day | Task | Status |
|---|---|---|
| Thu Apr 30 | Repo + spec + Xcode project init | ☐ |
| Fri May 1 | SwiftData models (Exercise, Workout, SetEntry, etc.) | ☐ |
| Sat May 2 | Bundled exercise library JSON (200 exercises, hand-curated) | ☐ |
| Sun May 3 | Exercise list UI (search, filter by muscle/equipment) | ☐ |
| Mon May 4 | Workout creation flow, exercise selection | ☐ |
| Tue May 5 | Set logging UI (reps, weight, RPE input) | ☐ |
| Wed May 6 | Buffer / catch-up day | ☐ |

**Exit criteria:** Can launch app, browse exercises, start a workout, log a set, see it persist after relaunch.

---

## Week 2 (May 7 – May 13) — Core Loop

**Goal:** Full workout flow with timer, PRs, HealthKit write.

| Day | Task | Status |
|---|---|---|
| Thu May 7 | Rest timer (in-app + lock screen) | ☐ |
| Fri May 8 | Plate calculator | ☐ |
| Sat May 9 | PR detection (1RM, e1RM via Epley) | ☐ |
| Sun May 10 | History view (calendar + list) | ☐ |
| Mon May 11 | HealthKit write (workout type, calories, HR) | ☐ |
| Tue May 12 | Programs (built-in 5/3/1, PPL, Starting Strength) | ☐ |
| Wed May 13 | Buffer / polish | ☐ |

**Exit criteria:** Complete workout, see PRs, view history, workout appears in Apple Health.

---

## Week 3 (May 14 – May 20) — watchOS

**Goal:** Standalone Watch app for set logging.

| Day | Task | Status |
|---|---|---|
| Thu May 14 | watchOS target setup, shared models | ☐ |
| Fri May 15 | Watch workout list, start workout | ☐ |
| Sat May 16 | Watch set logging (digital crown for weight/reps) | ☐ |
| Sun May 17 | Rest timer with haptics on Watch | ☐ |
| Mon May 18 | Heart rate during conditioning | ☐ |
| Tue May 19 | WatchConnectivity sync to phone | ☐ |
| Wed May 20 | Buffer / Watch polish | ☐ |

**Exit criteria:** Log a full workout from Watch alone, sync to phone, see in history.

---

## Week 4 (May 21 – May 27) — Beta Prep

**Goal:** TestFlight, public repo, launch posts.

| Day | Task | Status |
|---|---|---|
| Thu May 21 | iCloud sync end-to-end test (2 devices) | ☐ |
| Fri May 22 | JSON + CSV export | ☐ |
| Sat May 23 | App icon, screenshots, TestFlight build | ☐ |
| Sun May 24 | App Store Connect setup, internal TestFlight | ☐ |
| Mon May 25 | External TestFlight (50 invites: r/Fitness friends) | ☐ |
| Tue May 26 | README polish, CONTRIBUTING.md, issue templates | ☐ |
| Wed May 27 | Public launch prep (HN, r/iOSProgramming, r/Fitness, X) | ☐ |

**Exit criteria:** App in TestFlight, GitHub public, first 50 testers have access.

---

## Week 5+ (May 28 onward) — Pro & Growth

**Not on critical path. Plan post-MVP.**

- Pro tier infrastructure (Convex, Sign in with Apple, StoreKit 2)
- AI form check (Gemini Flash integration)
- AI programming (Claude Haiku integration)
- Advanced analytics (fatigue, volume landmarks)
- Coach mode
- App Store launch (after 2 weeks of TestFlight feedback)
- Marketing: Hacker News post, r/Fitness AMA, X thread, Dan Koe-style essay
- Community: Discord server, GitHub Discussions, monthly "exercise library PR drive"

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| SwiftData CloudKit edge cases | Sync bugs | Use VersionedSchema from v1; test 2-device sync week 4 |
| HealthKit entitlement delays | Can't write workouts | Submit entitlement request day 1; fallback: read-only week 1 |
| Watch app eats time | Beta slips | Watch is week 3; if behind, ship MVP without Watch and add post-beta |
| Exercise library quality | Looks amateur | Seed 200 hand-curated exercises with correct muscle groups; community can expand |
| TestFlight rejection | Beta blocked | Standard subscription app; no precedent for rejection |

---

## Definition of Done — TestFlight Beta

- [ ] User can log a complete workout (lifting + conditioning) on iPhone
- [ ] User can log a workout from Watch alone
- [ ] iCloud sync works between 2 devices
- [ ] Workouts appear in Apple Health
- [ ] PRs detected and surfaced
- [ ] History viewable, exportable
- [ ] No crashes in 1-week of dogfooding
- [ ] App icon, screenshots, App Store metadata in place
- [ ] GitHub repo public, README + LICENSE + CONTRIBUTING in place

---

## Tracking

Update this file at end of each day. Move tasks between weeks freely. The plan is a guide, not a contract.
