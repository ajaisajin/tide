# Design

## Context

See proposal.md for motivation. The constraints that shape the approach:

- One developer working with an AI pair. No designer or motion designer. The developer chose Flutter, in line with the technical specification.
- Development machine is Linux with Flutter 3.44.9 (Dart 3.12.2), Android SDK 36, an Android emulator (`Pixel_7_API_36`, with KVM) and Chrome. The Linux desktop toolchain is not installed.
- The developer's only phone is an iPhone. Flutter cannot build for iOS without macOS and Xcode, so the app is not run on a real phone in this change.
- The project directory holds documents, `openspec/` and an empty git repository. Its path contains a space (`Ai native/Tide`).
- Three source documents exist at the project root: the BRD, the technical specification, and an HTML design prototype. The prototype's layout, colours, fonts, copy and money logic are the visual and behavioural reference for this change.

## Goals / Non-Goals

**Goals:**

- A Flutter app that runs on the Android emulator and in Chrome with hot reload.
- Liquid animation that repaints without rebuilding the widget tree.
- Budget maths that is pure Dart, unit-tested and reusable unchanged when storage arrives.
- An entry shape that matches the technical specification's `transactions` table, so the next change can add a database without reshaping data.
- A fair comparison of the three amount-entry methods.
- As much behaviour as possible covered by automated unit and widget tests, since nothing can be checked on a real phone.

**Non-Goals:**

- Running on an iPhone, or any iOS build.
- Physics for pebbles (rigid bodies, buoyancy). Pebbles are laid out, not simulated.
- A 64-point wave simulation. A simpler model is tried first (see decision 4).
- Navigation between multiple routes. There are two layers only.
- Tuning for real-device performance.
- Home-screen pebbles opening a category. They are display-only in this change.

## Decisions

### 1. Flutter, checked on the Android emulator and Chrome

Flutter is the developer's choice and the technical specification's. Its own renderer (Impeller) and fragment shaders suit a one-screen, canvas-like app.

The cost is reach: with Linux and an iPhone, nothing runs on real hardware. The Android emulator is the main target because it supports the accelerometer (through its virtual sensor controls) and the Android code paths. Chrome is a second, faster target for layout work; it has no motion sensor or haptics.

- *Expo with Expo Go*: would run on the iPhone from Linux. Set aside at the developer's direction.
- *Linux desktop target*: needs clang, CMake, ninja and pkg-config installed, and adds nothing the emulator and Chrome do not cover.

### 2. App at the project root, under git

`flutter create --project-name tide --platforms android,ios,web .` is run at the project root, beside `openspec/` and the three documents, which are left where they are. The project name is given explicitly because the folder name `Tide` is not a valid Dart package name. The `ios` folder is generated so an iOS build is possible later without restructuring, though nothing builds it now.

- *A subfolder such as `app/`*: only useful if a backend were to share the repository, and v1 has none.

### 3. One home widget, two layers, no router

The Vessel is always in the tree. The log flow is an overlay in a `Stack` above it, animated in and out. A single piece of state says which layer is on top.

- *Navigator routes or `go_router`*: built for many screens and deep links, which this change does not have, and a pushed route would cover the Vessel and complicate keeping the liquid running underneath.

### 4. Liquid drawn by a fragment shader, driven by three springs

A full-screen `CustomPaint` runs one GLSL fragment shader, declared under `shaders:` in `pubspec.yaml` and loaded with `FragmentProgram`. Its inputs are time, fill height, surface lean, slosh amplitude and the band colour. The surface line is the fill height plus the lean slope plus a few summed sine waves scaled by the slosh amplitude; below the line the shader paints a depth gradient and a highlight along the surface.

Fill height, lean and slosh are each a damped spring. This replaces the technical specification's 64-point wave simulation for now: three numbers are easy to tune by hand, and the renderer can be swapped later without touching anything else.

- *A `Path` rebuilt every frame*: simpler, but depth shading and highlights need extra layers. Kept as the fallback if the shader misbehaves on a target.
- *Rive (technical specification)*: needs assets authored by a designer.

### 5. Motion runs on a ticker and repaints only the canvas

A single `Ticker` advances the springs each frame and updates a `ChangeNotifier` that is passed to the painter as its `repaint` listenable. The liquid therefore repaints every frame without any widget rebuild. The canvas sits in its own `RepaintBoundary` so text and pebbles above it are not repainted with it.

Tilt comes from the accelerometer through `sensors_plus`, low-pass filtered, and is subscribed only while the Vessel layer is on top. On web, where no sensor exists, lean stays at zero.

### 6. Text and pebbles are ordinary widgets above the canvas

The remaining amount, labels, handle, pebbles, toast and the whole log flow are widgets layered over the canvas. That gives real text rendering, text scaling and `Semantics` labels without extra work. Pebble size and the "sunk" offset use implicit animations.

- *Drawing pebbles and text in the shader or painter*: would allow water to refract them, at the cost of rebuilding accessibility by hand.

### 7. Pure budget library, Riverpod state, entries in memory

- A `budget` library of pure functions takes the budget, the entries and a date, and returns the figures in the `budget-status` spec. It imports nothing from Flutter and is covered by unit tests.
- Amounts are integers in paise everywhere inside the app, formatted only at the point of display. The Indian-grouping formatter is written by hand to avoid a dependency for one function.
- State is held with Riverpod, as the technical specification chose: entries, categories, budget, and timing records. It is seeded at launch with the prototype's twelve October entries, six categories and a ₹30,000 budget, re-dated into the current month so the figures stay meaningful.
- The current date is read through an injectable clock so tests can fix it.
- An entry has `id`, `type`, `amountMinor`, `categoryId`, `note`, `occurredAt` and `source`, following the technical specification's `transactions` table.

- *Drift and SQLite now*: deferred on purpose, to keep this change about the interaction.

### 8. Log flow layout: chips always shown, ring and pad share one area

All three methods plus six pebbles do not fit on one phone screen at usable sizes. The layout from top to bottom is: mode switch and Cancel, the amount, a row of chips, a switch between Ring and Pad that remembers the last choice, the ring or the pad, then the pebble grid. The note is collapsed behind an "Add note" link.

- The amount starts at ₹0, not the prototype's ₹250, so the pad's first digit and the "amount must be set" rule behave predictably.
- The ring steps by ₹10 when turned slowly, ₹100 at medium speed and ₹1,000 when spun. Amounts not divisible by 10 are entered with the pad.
- The method recorded for timing is whichever control changed the amount last.
- The prototype's step buttons (−100, +10, +100, +1k, +5k) are not carried over; the pad supersedes them.

### 9. Pull-down trigger stays out of the system's edge

A vertical drag on the Vessel opens the log flow once the finger has travelled 80 logical pixels downward. It only begins below the top safe-area inset, so it never competes with the system's notification gesture. A droplet follows the finger during the drag to show what will happen.

### 10. Haptics from the framework

Haptic ticks and pulses use Flutter's built-in `HapticFeedback`, called through a small wrapper so tests can record the calls. No haptics package is added.

### 11. Still water and the frame-rate readout

A frame-timings callback keeps a rolling average of frame time. Above 20 ms for two seconds, a flag switches the painter to a flat level and stops the sensor until next launch. The platform's reduce-motion setting (`MediaQuery.disableAnimations`) sets the same flag. A small frame-rate readout is shown in debug builds only.

### 12. Timing instrument is part of the prototype, clearly marked

The log flow stamps the moment it opens and the moment an entry is filed. A "Timings" control on the home screen opens the summary. It is labelled as a test instrument and is expected to move into a settings or debug area once the gate is passed.

### 13. Fonts and colours

Bricolage Grotesque (display) and DM Sans (text) are added as font files under `assets/fonts` and declared in `pubspec.yaml`, not fetched at run time. Both are under the SIL Open Font License, and their licence files are kept beside them. Colour tokens are taken from the prototype: ink `#0E1420`, teal `#2BB5A6`, amber `#E9A23B`, coral `#E86A5A`, text `#EEF2F5`.

### 14. Testing: widget tests carry what the phone cannot

Unit tests cover the budget library, chips, timing maths and amount rules. Widget tests cover the screens: figures shown, the overspent state, filing, refusal at ₹0, income, undo and its 10-second window (with a fake clock), still-water mode and `Semantics` labels. The shader is not asserted in tests; the liquid's look and motion are checked by eye on the emulator.

## Risks / Trade-offs

- [Nothing runs on a real phone, so the 3-second gate is not truly tested] → The timing instrument is still built, and emulator timings with a mouse are recorded as indicative only. A release APK is built at the end so the app can be installed on any borrowed Android phone. This is the main cost of the stack choice on this setup.
- [Haptics cannot be felt on an emulator or in Chrome] → Widget tests assert that the right haptic call fires at the right moment. The feel is unverified.
- [Tilt on the emulator is set with sliders, not by hand] → Enough to confirm the surface leans and settles. The feel is unverified.
- [The emulator's frame rate says little about real devices] → Accepted. The still-water fallback is the safety net, and the 60 fps target on a 4 GB Android phone stays unverified.
- [Fragment shaders differ slightly between Android and web renderers] → Android emulator is the reference. If the shader fails on web, Chrome falls back to the `Path` renderer and this is noted.
- [The space in the project path breaks a build tool] → If Gradle or another tool fails on the path, move the repository to a path without spaces before going further.
- [Three springs look less like water than a wave simulation] → Accepted for the prototype. The renderer's inputs are the same either way, so it can be replaced alone.
- [Entries vanish on restart, so chips and timings cannot build up over days] → Accepted. Persistence is the next change.

## Open Questions

- Which amount-entry methods survive. To be answered by timings on a real phone, which this change cannot produce.
- The ring's exact speed thresholds and step sizes. Tuned on the emulator now and again on a real phone later.
- How the app first reaches an iPhone (a borrowed Mac, a cloud Mac, or a cloud build service with the Apple Developer Program). Not needed for this change.
