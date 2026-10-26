# Jarvis — your everyday planning assistant

A native iOS 26 app built with SwiftUI and **Liquid Glass**. Jarvis shows what you have to do
today and this week, understands plain-English plans, reads your briefing out loud and keeps
everything moving with smooth, physics-based animation.

<p align="center"><img src="Jarvis/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="Jarvis app icon"></p>

<p align="center">
  <img src="docs/screenshots/1-today-dark.png" width="240" alt="Today, dark">
  <img src="docs/screenshots/2-week-dark.png" width="240" alt="Week, dark">
  <img src="docs/screenshots/3-ask-dark.png" width="240" alt="Ask Jarvis, dark">
</p>
<p align="center">
  <img src="docs/screenshots/4-today-light.png" width="240" alt="Today, light">
  <img src="docs/screenshots/5-week-light.png" width="240" alt="Week, light">
  <img src="docs/screenshots/6-settings-light.png" width="240" alt="Settings, light">
</p>

## Features

**Today**
- A living Jarvis orb: a swirling plasma core behind a Liquid Glass sphere with orbiting HUD
  rings. Tap it to hear your briefing; it spins up while Jarvis talks.
- A briefing that types itself out: what's next, what's done, what's important and your
  longest free window.
- Glass stat tiles (progress ring, planned time, free time left) and a hero "Happening now / Up
  next" card with a live progress bar.
- A timeline with a glowing rail, a live "now" marker and glass cards. Tap to edit, tap the
  circle to complete (with haptics and a bounce), long-press for Move to Tomorrow, Duplicate
  and Delete.

**Week**
- A glass day strip whose selection capsule glides between days. Swipe it to change week.
- A "Week pulse" bar chart of planned vs. done per day. Tap a bar to jump to that day.
- Day sections blur-transition as you move between days.

**Ask Jarvis** (the glass bar above the tab bar)
- Type naturally and see a live preview of what Jarvis understood before you send:
  - `Gym tomorrow at 7am for 1h`
  - `Team meeting friday 10:30-11:15 #work`
  - `Dentist next tuesday 3pm!` (a trailing `!` marks it important)
  - `Call mom tonight` · `Pay rent oct 31` · `Coffee in 30 min` · `Exam on the 30th`
- Ask questions: `What's on tomorrow?`, `Am I free friday afternoon?`, `Brief me on my week`.
- `Call me Joel` sets your name for greetings.
- The send button morphs out of the text field using `GlassEffectContainer` and `glassEffectID`.
  Undo is one tap.

**Also**
- Calendar events (EventKit, read-only) appear alongside your plans.
- Optional reminders before each timed plan.
- A British voice by default; American, Australian, Irish and Indian accents are available.
- Light and dark appearances are drawn over an animated mesh-gradient aurora.
- Respects Reduce Motion. Data is stored on-device with SwiftData.
- "Load a sample week" lets you explore the app straight away.

## Requirements

- **Xcode 26** or later
- **iOS 26** or later (Liquid Glass APIs)

## Run it

1. Open `Jarvis.xcodeproj` in Xcode 26.
2. Select the **Jarvis** target → *Signing & Capabilities* → choose your Team. If the bundle ID
   `com.joelin.jarvis` is taken, change it to something unique.
3. Pick an iPhone simulator or your device and press **⌘R**.
4. On first launch, tap **Load a sample week** (or open **Ask Jarvis**) to get started.

To run on your own iPhone, enable *Developer Mode* on the phone (Settings → Privacy & Security).

## Project layout

```
Jarvis/
  App/            JarvisApp (entry point), RootView (tabs, glass accessory, sheets)
  Models/         Plan (SwiftData), categories, AgendaItem, formatting & theme
  Services/       PlanParser (natural language), Briefing (what Jarvis says),
                  CalendarService (EventKit), JarvisVoice (speech),
                  ReminderScheduler (notifications), JarvisStore, SampleData
  Views/
    Today/        Orb header, briefing, stats, focus card, timeline
    Week/         Day strip, week pulse chart, day section
    Ask/          Conversational assistant with live parsing preview
    Editor/       Create / edit plan sheet
    Settings/     Name, voice, calendar, reminders, data
    Components/   Aurora background, Jarvis orb, typewriter text, glass cards
```

The project uses Xcode's synchronized folders, so new files in `Jarvis/` are picked up
automatically. CI builds the app for the iOS Simulator on every push
(`.github/workflows/build.yml`). To refresh the screenshots above, run the *Screenshots*
workflow or push a commit whose message contains `[screenshots]`.
