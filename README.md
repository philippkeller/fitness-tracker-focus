# FocusLift

A gym tracker you run with the **phone locked in your pocket**. It talks to you through your AirPods and you control it by **pressing the AirPods stem**.

## Workout flow

1. Start a routine. The voice says the first exercise, its setup note, the set, the kg and the reps.
2. Do the set and **press once**. The set is logged and the rest timer starts. The voice says the rest time and what comes next (with the setup note when it's a new exercise).
3. At 10 seconds left you hear "Noch 10 Sekunden", then "Los! Satz 2 von 3 …".
4. Press once during a rest to skip it.
5. At the end, open the app and tap **Finish**. You'll see your records (heaviest weight, most reps, best set kg × reps).

| AirPods press | Action |
|---|---|
| 1× | Set done / skip rest |
| 2× | Repeat the last announcement (time left + next set) |
| 3× | Say the time |

The lock screen's Now Playing widget shows the current exercise, or the rest countdown as a progress bar.

### Why the music has to play in this app

iOS sends AirPods presses only to the app that is currently playing audio. If Amperfy or Spotify plays, they get the presses. FocusLift therefore streams from your **Navidrome/Subsonic server** (the one Amperfy uses) itself: Settings → Music. With no music, the app plays silence in the background to keep receiving presses.

## Features

- Routines: add, rename, reorder and delete exercises. Each set has its own kg, reps and rest time.
- A setup note per exercise (the yellow note in Strong), read aloud before the exercise.
- A "Previous" column showing last time's sets.
- Records at the end of each workout and in history.
- "Finish & update routine" saves today's weights, reps and exercise order to the routine.
- Strong import: Strong → Settings → Export Strong Data. Then in FocusLift: Settings → Import Strong CSV. This imports history (used for Previous and records) and creates one routine per Strong workout name.
- **App blocking**: Settings → Focus → choose apps (X, Instagram, …). While a workout runs they show a Screen Time block screen; they unlock when you finish or discard. Uses Apple's Family Controls (Screen Time) API, approved once with Face ID.
- **ElevenLabs voice**: Settings → Voice. Paste your API key and optionally the settings from the Voice Lab (below). Each sentence ("Satz 2 von 3.", "17,5 Kilo, 10 Wiederholungen.") is generated once and saved on the phone, so repeated announcements cost no credits and work without signal. Tap *Prepare voice for routines* on Wi-Fi after changing a routine. If a sentence can't be generated, the iPhone voice reads the announcement.
- **Music**: Artists → song, a random mix, or a playlist from your Navidrome server.
- Data is stored in a single JSON file (Files app → On My iPhone → FocusLift). You can also export it from Settings.

## Build (Xcode 16 or newer)

1. Open `FocusLift.xcodeproj`.
2. Select the **FocusLift** target → *Signing & Capabilities*. Choose your **Team**. If Xcode complains that the bundle identifier is taken, change it (e.g. `com.yourname.focuslift`). The **Family Controls** capability should appear automatically (from `Config/FocusLift.entitlements`); if Xcode shows a signing error about it, click *+ Capability* → *Family Controls*. Development builds don't need Apple's approval.
3. Plug in your iPhone, select it as the run destination and press **Run** (⌘R).
4. On first install, trust the developer certificate on the iPhone (Settings → General → VPN & Device Management) and enable Developer Mode if asked.

## Voice Lab

`tools/voice-lab.html` is a page for trying ElevenLabs voices, models and settings on FocusLift's real announcements without rebuilding the app. Open it in a browser, paste your API key, generate, compare. *Copy* under "Settings for FocusLift", then in the app: Settings → Voice → *Paste settings from Voice Lab*.

Without ElevenLabs: download an *Enhanced* or *Premium* German voice in iOS Settings → Accessibility → Spoken Content → Voices. It sounds much better than the default voice.

## Code map

- `Workout/WorkoutEngine.swift`: state machine (lifting → resting → …), timer, announcements
- `Audio/AudioController.swift`: audio session, silent loop, AirPods remote commands, lock screen info
- `Audio/Phrases.swift`: everything the voice says (DE/EN)
- `Audio/ElevenLabs.swift`: voice settings, API key in the Keychain, per-sentence audio cache
- `Music/`: Subsonic client and in-app music player
- `Store/AppStore.swift`: data, persistence, "previous" lookups, records
- `Import/StrongImporter.swift`: Strong CSV import
- `Views/`: SwiftUI screens
