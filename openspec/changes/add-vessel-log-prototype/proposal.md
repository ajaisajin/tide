# Proposal

## Why

The BRD gates the whole build on one question: can a person log an expense in 3 seconds or less, unaided, on a home screen that shows budget status as a liquid level. Nothing runs today; the project holds a BRD, a technical specification and an HTML design prototype. This change produces the first thing that runs on a real phone so that gate can be tested before any ledger, sync or capture work starts.

The technical specification chose Flutter, and the developer has confirmed that choice. The project is one developer on Linux whose only phone is an iPhone, which a Flutter build cannot reach without a Mac, so this change is built and checked on the Android emulator and in Chrome.

## What Changes

- Create the Tide mobile app as a Flutter (Dart) project, as the technical specification sets out, run on the Android emulator and in Chrome from a Linux machine.
- Add the Vessel home screen: a full-screen liquid whose level, colour and mood label show how much of the month's budget is left, with the remaining amount and the safe-to-spend figure always visible, category pebbles, and a distinct overspent state.
- Add liquid motion: idle waves, a slosh when the phone tilts, a drain or fill animation when an entry is saved, and a "still water" mode for reduced motion or slow frames.
- Add the log flow: opened by pulling down on the Vessel or tapping a visible handle, an amount, one tap on a category pebble to file an expense, an income mode, and a 10-second undo.
- Offer three amount-entry methods side by side so they can be timed against each other: the spinning amount ring, a custom number pad, and frequent-amount chips. The slowest are expected to be removed in a later change.
- Measure and show time-to-log per entry and the median per amount-entry method, since that is the number the gate depends on.
- Seed the app with one month of sample data held in memory. Entries are lost when the app restarts.

Deliberate departures from the BRD, each taken from the HTML prototype or from the exploration that preceded this change:

- The remaining amount is always on screen, instead of "numbers on demand".
- The log flow opens with a pull down on the Vessel, not a swipe from the top screen edge, which iOS reserves for Notification Centre.
- Undo is a button in a toast. Shake-to-undo is dropped.
- Pebbles are sized by share of category limit used, and the log screen uses a fixed grid of equal-sized pebbles.

Out of scope for this change: saving data between launches, the command dial, the Time River, the category detail screen, goals, pools, recurring bills, notifications, accounts and sync, SMS or share-sheet capture, voice, receipt scan, export, app lock, Hindi, the light theme, running on an iPhone, performance tuning on real devices and store builds.

## Capabilities

### New Capabilities

- `budget-status`: how Tide derives the month's position from the budget and the entries: amount available, amount remaining, fill level, status band and mood, safe-to-spend today, and each category's spend against its limit.
- `vessel-home`: the home screen that presents budget status as a liquid vessel, including pebbles, the overspent state, liquid motion, tilt response and still-water mode.
- `expense-logging`: recording an expense or income entry, covering how the log flow opens, amount entry, filing to a category, undo, and time-to-log measurement.

### Modified Capabilities

None. The project has no existing specs.

## Impact

- **New code**: a new Flutter app at the project root. There is no existing code to change.
- **Dependencies**: Flutter 3.44 and Dart 3.12 (already installed), `flutter_riverpod`, `sensors_plus`, and the Bricolage Grotesque and DM Sans font files bundled as assets. Haptics, gestures and fragment shaders come with Flutter itself.
- **Tooling**: the installed Android SDK and the existing `Pixel_7_API_36` emulator, plus Chrome. No Mac, Apple Developer account or backend is needed.
- **Technical specification**: followed for Flutter, Riverpod and the Vessel renderer design. Its Drift database, Rive animations and backend are not used in this change; Rive is replaced by code-drawn motion because there is no motion designer.
- **Open risks carried forward**: the app is not run on a real phone in this change. The 3-second logging gate, haptic feel, tilt feel and frame rate on a 4 GB Android phone all stay unverified on hardware until an Android phone is borrowed or an iOS build is arranged through a Mac or a cloud build service.
