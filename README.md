# PulseBuddy

![Swift](https://img.shields.io/badge/swift-6.2-brightgreen.svg) ![Xcode 26.0+](https://img.shields.io/badge/xcode-26.0%2B-blue.svg) ![iOS 18.0+](https://img.shields.io/badge/iOS-18.0%2B-blue.svg) ![watchOS 11.0+](https://img.shields.io/badge/watchOS-11.0%2B-blue.svg) ![CareKit 4.0+](https://img.shields.io/badge/CareKit-4.0%2B-red.svg) [![ci](https://github.com/netreconlab/CareKitSample-ParseCareKit/actions/workflows/ci.yml/badge.svg)](https://github.com/netreconlab/CareKitSample-ParseCareKit/actions/workflows/ci.yml)

An iOS/watchOS care app for ADHD patients, built on [CareKit](https://github.com/carekit-apple/CareKit) and [ParseCareKit](https://github.com/netreconlab/ParseCareKit). Patients track medication, mood, focus, exercise, and cognitive check-ins. Clinicians assign care plans and review patient progress. All data syncs to a Parse backend in real time.

> **Use at your own risk. There is no promise that this is HIPAA compliant and we are not responsible for any mishandling of your data.**

---

## Screenshots

*Suggested screenshots to take:*

1. **Care View (patient)** — daily task list showing medication, mood, sleep, and exercise cards  
2. **Detection notification** — lock screen / notification center with the "Are you exercising?" prompt and Log / Dismiss actions  
3. **In-app tracking banner** — the blue "Tracking exercise · Dismiss" banner overlaid at the top of Care View while a session is active  
4. **IKBE session start sheet** — the bottom sheet listing the user's predefined focus types (e.g. "Focus writing", "Reading", "Chores")  
5. **Dynamic Island / Live Activity** — the in-progress session timer visible system-wide while an IKBE session is running  
6. **Apple Watch companion** — medication and exercise cards on the watch face  
7. **Insights View** — outcome history charts for steps, stress, and attention  
8. **Clinician tab** — patient list and care plan assignment screen  

---

## Features

### Daily Care Tasks
Patients complete a structured daily card list covering:

- **Medication** — methylphenidate log with time-of-dose tracking
- **Behavioral tracking** — focus log, distraction log, mood, sleep, stress
- **Movement** — cardio and stretch cards; step count via HealthKit
- **Adaptive prompts** — refocus prompt, breathing exercise, take-a-break card
- **Assessments** — Stroop Test, inattention/hyperactivity/impulsivity surveys, weekly reflection

### IKBE — Execution-Function Support
*"I Know, But Execution"* — the core feature designed around the ADHD pattern where users know what they need to do but struggle to start and track it.

Users predefine a small set of activity types (e.g. "Focus writing", "Reading", "Chores"). Starting a session is **1–2 taps**: tap the hero card → pick a type → session begins with haptic confirmation. There is intentionally no confirmation dialog — start friction is kept as low as possible.

While a session is active, a **Live Activity** (Dynamic Island + lock screen) shows the session type and elapsed time so it is always visible without opening the app. An Apple Watch companion view shows the current session with an End button.

Only one session can be active at a time — starting a second prompts the user to end the current one, matching the ADHD reality of a single primary focus task.

Each session is stored as an `OCKOutcome` with `startedAt`, `endedAt`, and an `autoEnded` flag for sessions that exceeded the 4-hour global timeout (auto-ended outcomes are treated as lower-confidence data in dashboards).

**Planned extensions:**
- Per-type duration targets and weekly goal charts in Insights View
- `TriggerSource` metadata (`manual` / `notification` / `auto`) for later HealthKit/motion auto-detection integration
- watchOS session-start support (current Watch MVP is view + End only)
- Types management tab (create / rename / reorder IKBE types)

### Passive Detection (HealthKit-Driven)
The app monitors HealthKit in the background and nudges users to log sessions they forgot to start, without requiring any manual action first.

| Detector | Signal | Flow |
|---|---|---|
| **Exercise** | ≥ 300 steps in 5 min, no exercise task active in the past 20 min | Stage 1: "Are you exercising?" [Log / Dismiss] → if confirmed, monitors for movement to stop → Stage 2: "Did you finish?" [Still going / Yes, ended] |
| **Mood spike** | Heart rate ≥ 25 bpm above resting baseline while sedentary | Single stage: "Elevated HR — strong emotion?" [Log / Dismiss] |

Both detectors run fully in the background via `HKObserverQuery` + background delivery. A persistent banner appears in-app while an exercise session is being tracked. If the user never responds to a prompt, an `isUnconfirmed=true` outcome is written automatically so data is not silently lost.

**Planned extensions:**
- Personalized step thresholds computed from the user's rolling 7-day baseline
- Stress detection from HRV data
- Manual end button on the in-app tracking banner (alongside Dismiss)

### Clinician View
- Patient list and detail view
- Care plan creation and assignment
- Contact management
- Push notification delivery to patients

### Apple Watch Companion
Medication, cardio, and stretch cards sync to watchOS. Active IKBE sessions display on-watch with an End button.

---

## Requirements

- Xcode 26.0+
- iOS 18.0+ device or simulator (HealthKit features require a real device)
- watchOS 11.0+ (Apple Watch companion)
- A running [parse-hipaa](https://github.com/netreconlab/parse-hipaa) server (local or cloud)

---

## Setup

### 1. Start a Parse server

**Local (Docker) — recommended for development:**

```bash
git clone https://github.com/netreconlab/parse-hipaa
cd parse-hipaa
docker-compose up
```

Wait for `parse-server running on port 1337.` — takes 1–2 minutes on first run while Postgres initialises.  
To use MongoDB instead: `docker-compose -f docker-compose.mongo.yml up`

**Cloud (Heroku):** use the [one-button deploy](https://github.com/netreconlab/parse-hipaa#heroku).

### 2. Open the project

```bash
open OCKSample.xcodeproj
```

In **Signing & Capabilities**, set your Team and Bundle Identifier, then run. The app connects to `http://localhost:1337/parse` by default.

To point at a different server, edit `ParseCareKit.plist` under Supporting Files and update the `Server` key.

### 3. (Optional) View your data in Parse Dashboard

Open `http://localhost:4040/dashboard`  
Username: `parse` / Password: `1234`

Refresh the browser to see changes synced from the app.

---

## Configuration

Key flags in `OCKSample/Constants.swift`:

| Flag | Default | Effect |
|---|---|---|
| `isSyncingWithRemote` | `true` | `false` = iOS ↔ Watch sync only, no Parse server needed |
| `daysInThePastToGenerateSampleData` | `0` | Set to a negative number (e.g. `-30`) to seed historical outcomes for Insights View testing |

---

## Architecture

```
OCKSample/
├── AppDelegate.swift               — app lifecycle; owns detectors, notification manager, store coordinator
├── Detection/
│   ├── ExerciseDetector.swift      — step-burst detection, 4-phase state machine, persistence
│   ├── HeartRateAnomalyDetector.swift — HR spike detection, resting-baseline personalisation
│   ├── DetectionNotificationManager.swift — UNUserNotificationCenter setup, action routing
│   ├── DetectedExerciseRecorder.swift — writes OCKOutcome for detected exercise sessions
│   └── DetectedMoodRecorder.swift  — writes OCKOutcome for detected mood spikes
├── Extensions/
│   ├── OCKStore+SampleData.swift   — task and care plan seeding on first launch
│   └── OCKHealthKitPassthroughStore.swift — HealthKit task bridge
├── Main/
│   ├── Care/                       — patient daily task list (CareView + CareViewController)
│   ├── Careplans/                  — care plan management
│   ├── Insights/                   — outcome history charts
│   ├── Notifications/              — in-app notification list
│   ├── Profile/                    — patient profile and contact card
│   └── Surveys/                    — onboarding consent, Stroop Test, range of motion
├── Models/
│   ├── TaskID.swift                — all task identifiers; exerciseRelated and moodRelated suppression lists
│   ├── CarePlanID.swift            — care plan identifiers
│   └── Parse/                      — Patient, Clinician, User, Outcome Parse object models
└── WatchConnectivity/              — iOS ↔ watchOS sync delegates
```

ParseCareKit synchronises these entities to Parse:

- [x] OCKPatient ↔ Patient
- [x] OCKCarePlan ↔ CarePlan
- [x] OCKContact ↔ Contact
- [x] OCKTask ↔ Task
- [x] OCKHealthKitTask ↔ HealthKitTask
- [x] OCKOutcome ↔ Outcome
- [x] OCKRevisionRecord ↔ RevisionRecord

---

## Going to Production

Once your parse-hipaa server is deployed behind HTTPS:

1. Open `ParseCareKit.plist` → update `Server` to your cloud URL
2. Open `Info.plist` → remove `App Transport Security Settings` and all child keys (required for App Store submission and HIPAA compliance — the local-only exception must not ship to production)
3. Run the [parse-hipaa production optimisation scripts](https://github.com/netreconlab/parse-hipaa#running-in-production-for-parsecarekit) for indexed Cloud queries

---

## Related Projects

- [CareKit](https://github.com/carekit-apple/CareKit)
- [ParseCareKit](https://github.com/netreconlab/ParseCareKit)
- [CareKitEssentials](https://github.com/netreconlab/CareKitEssentials)
- [parse-hipaa](https://github.com/netreconlab/parse-hipaa)
- [parse-hipaa-dashboard](https://github.com/netreconlab/parse-hipaa-dashboard)
