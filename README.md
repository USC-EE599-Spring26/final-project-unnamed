# PulseBuddy

![Swift](https://img.shields.io/badge/swift-6.2-brightgreen.svg) ![Xcode 26.0+](https://img.shields.io/badge/xcode-26.0%2B-blue.svg) ![iOS 18.0+](https://img.shields.io/badge/iOS-18.0%2B-blue.svg) ![watchOS 11.0+](https://img.shields.io/badge/watchOS-11.0%2B-blue.svg) ![CareKit 4.0+](https://img.shields.io/badge/CareKit-4.0%2B-red.svg) [![ci](https://github.com/netreconlab/CareKitSample-ParseCareKit/actions/workflows/ci.yml/badge.svg)](https://github.com/netreconlab/CareKitSample-ParseCareKit/actions/workflows/ci.yml)

An iOS/watchOS care app for ADHD patients, built on [CareKit](https://github.com/carekit-apple/CareKit) and [ParseCareKit](https://github.com/netreconlab/ParseCareKit). Patients track medication, mood, focus, exercise, and cognitive check-ins. Clinicians assign care plans and review patient progress. All data syncs to a Parse backend in real time.

> **Use at your own risk. There is no promise that this is HIPAA compliant and we are not responsible for any mishandling of your data.**

---

## Screenshots

*Suggested screenshots to take:*

1. **Onboarding** — the ResearchKit consent + HealthKit permission screens  
2. **Care View (patient)** — daily task list showing tip card, medication, mood, sleep, and exercise cards  
3. **Detection notification** — lock screen with the "Are you exercising?" prompt and Log / Dismiss actions (long-press to reveal)  
4. **In-app tracking banner** — the blue "Tracking exercise · Dismiss" banner overlaid at the top of Care View while a session is active  
5. **Insights View** — bar charts for steps, stress, attention, and routine with interval picker  
6. **Stroop Test** — the ResearchKit cognitive interference task in progress  
7. **Profile** — the all-in-one form showing photo, name, and contact fields  
8. **Clinician tab** — patient list and care plan assignment screen  
9. **Apple Watch companion** — medication and exercise cards on the watch face  

---

## Features

### Onboarding
First-launch flow built on ResearchKit guides new users through:
- **Consent** — informed consent form with review and signature step
- **HealthKit permissions** — step count, heart rate, resting heart rate requested during onboarding (required for passive detection)
- **Care plan assignment** — default ADHD care plans seeded on completion

### Authentication
- Sign up or log in with either **username or email**
- **Role selection** at sign-up: patient or clinician — each role gets a different tab layout on next launch

### Daily Care Tasks
Patients complete a structured daily card list covering:

- **Medication** — methylphenidate intake log
- **Behavioral tracking** — focus log, distraction log, mood, sleep, stress
- **Movement** — cardio and stretch cards; step count and heart rate via HealthKit
- **Adaptive prompts** — refocus prompt, breathing exercise, take-a-break card
- **Tip card** — featured content card at the top of Care View; tapping opens a curated ADHD resource in-browser

### Cognitive Assessments (ResearchKit)
- **Stroop Test** — measures focused attention and cognitive flexibility; user taps the color a word is printed in, not the word itself
- **ADHD daily check-in** — structured daily symptom survey
- **Quality of Life survey** — standardized self-assessment
- **Weekly reflection** — longer trend check-in

### Insights
Swift Charts bar charts visualise outcome history for steps, stress, attention, and routine. Supports day/week/month interval switching. Medication intake and inattention scores are overlaid on the same chart for correlation.

### Passive Detection (HealthKit-Driven)
The app monitors HealthKit in the background and nudges users to log sessions they forgot to start, without any manual action required.

| Detector | Signal | Flow |
|---|---|---|
| **Exercise** | ≥ 300 steps in 5 min, no exercise task logged in the past 20 min | Stage 1: "Are you exercising?" [Log / Dismiss] → confirmed → monitors for movement to stop → Stage 2: "Did you finish?" [Still going / Yes, ended] |
| **Mood spike** | HR ≥ 25 bpm above resting baseline while sedentary | Single stage: "Elevated HR — strong emotion?" [Log / Dismiss] |

Both detectors run fully in the background via `HKObserverQuery` + background delivery. A persistent banner appears at the top of Care View while an exercise session is being tracked. If the user never responds, an `isUnconfirmed=true` outcome is written automatically so no data is silently dropped.

**Planned extensions:**
- IKBE session scaffolding — 1-tap start for predefined focus types (e.g. "Focus writing", "Reading"), Live Activity showing elapsed time, Watch End button; each session stored as an `OCKOutcome` with `startedAt`/`endedAt`/`autoEnded` flags
- Personalized step thresholds computed from the user's rolling 7-day baseline
- Stress detection from HRV data
- Manual end button on the in-app tracking banner (alongside Dismiss)

### Task Management (Patient)
Patients can build their own care plan alongside the defaults:
- **Create tasks** — add a custom `OCKTask` (card type, schedule, care plan) or `OCKHealthKitTask` (linked to a HealthKit quantity type) from the Profile tab
- **Delete tasks** — long-press select in Care View, then delete; removed from both local store and Parse

### Profile
All patient-editable fields in one form: display name, given/family name, profile photo (camera or library), contact details (phone, email, address), and a summary bio. Changes sync to Parse immediately.

### Clinician View
Clinicians get a separate tab layout after login:
- **Patient list** — search and view all connected patients
- **Care plan management** — create care plans and assign them to patients
- **Clinician–patient connection** — link a clinician account to patient records
- **Push notifications** — send targeted notifications to individual patients

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
