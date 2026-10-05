# Tide

Tide is a personal expense tracker whose home screen is a liquid "vessel":
the fuller it is, the more of the month's budget is left. It is a Flutter app,
developed on Linux and checked on the Android emulator and in Chrome.

The app opens on the Vessel (`lib/home/home_screen.dart`,
`lib/vessel/`), seeded with a ₹30,000 budget and twelve sample entries.

## Prerequisites

- Flutter 3.44 or newer (Dart 3.12), on `PATH`
- Android SDK 36 with an emulator image; the commands below use the AVD
  `Pixel_7_API_36`
- Google Chrome, for the web target

The Linux desktop target is not set up. iOS needs macOS and Xcode and is not
built here.

## Commands

Run these from the project root.

```sh
# Fetch packages
flutter pub get

# Start the emulator, then wait until it has booted
flutter emulators --launch Pixel_7_API_36
adb wait-for-device
adb shell getprop sys.boot_completed   # prints 1 when ready

# Run on the emulator with hot reload (press r to reload, q to quit)
flutter run -d emulator-5554

# Run in Chrome
flutter run -d chrome

# Run the tests and the analyser
flutter test
flutter analyze
```

`flutter devices` lists the device ids if the emulator is not `emulator-5554`.

### Without an interactive terminal

```sh
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n app.tide.tide/.MainActivity

flutter build web        # output in build/web
```

### Moving the emulator's accelerometer

```sh
adb emu sensor set acceleration 6:7.5:1      # x:y:z in m/s², tilted
adb emu sensor set acceleration 0:9.78:0.81  # back to upright
```

### Reduce motion (still water)

Flutter's `disableAnimations` follows Android's transition animation scale:

```sh
adb shell settings put global transition_animation_scale 0   # still water
adb shell settings put global transition_animation_scale 1   # back to normal
```

### Starting in another state (development aid)

`TIDE_SCENARIO` starts the app in a chosen state so the Vessel can be checked
by eye. It works with `flutter run` and `flutter build`:

```sh
flutter run -d emulator-5554 --dart-define=TIDE_SCENARIO=overspent
```

Names: `full`, `low`, `calm`, `coral`, `overspent`, `overlimit`, and `cycle`
(files and removes entries every four seconds). See `lib/dev/scenario.dart`.

## Verification

Checked on 5 October 2026 by an independent pass over the three specs in
`openspec/changes/add-vessel-log-prototype/specs/`.

**The app has not been run on a physical phone.** Everything below was done on
the Android emulator (Pixel 7, API 36) driven with `adb shell input`, and in
headless Chrome driven over the DevTools Protocol. The 3-second logging target
is therefore not yet tested, and no time-to-log medians are recorded here.

`flutter analyze`: no issues. `flutter test`: 258 tests pass.

### Seen working on the emulator

- Home screen figures for the seeded month (₹13,601, October, Running lower,
  left of ₹30,000, 45% full, Safe today: ₹503); the liquid moving; full budget
  (text clear of the liquid, also while tilted) and fill level 0.02 (a band
  still showing), using the `full` and `low` scenario builds.
- Teal, amber and coral with the mood label changing at the same moment;
  logging down through amber and coral to exactly ₹0 ("Nearly dry"), into the
  overspent band (−₹2,000, growing to −₹8,000, "Safe today: ₹0") and back out
  with income.
- Pebbles: sizes, the 64-pixel minimum, and the lower position and coral
  outline when over the limit.
- The level draining and rising with a slosh after an expense, an income
  entry and an undo.
- Opening the log flow by handle and by pull-down; a short drag doing
  nothing; Cancel and the system back button.
- The pad (37; delete; refusing a seventh digit at ₹9,99,999), the ring (₹10,
  ₹100 and ₹1,000 steps by speed, anticlockwise, stopping at ₹0 and at
  ₹9,99,999), the chips, and Pad/Ring being remembered.
- Filing with one tap, the refusal at ₹0, income from a source, the toast
  with the time, Undo at 4 s and at 9.3 s, the toast still showing at about
  9.9 s and gone by 10.5 s, and a second entry's Undo leaving the first alone.
- The note field under the full on-screen keyboard: the field stays visible,
  the keyboard's done key, back, or a tap on the pad puts the keyboard away,
  and the pebbles are then reachable. Nothing overflowed.
- The Timings sheet: counts and medians per method, an undone entry left out,
  Clear.
- Tilt through `adb emu sensor set acceleration`: the surface leans, leans the
  other way and settles level. `dumpsys sensorservice` showed the app's
  accelerometer listener gone while the log flow was open and back afterwards.
- Reduce motion: flat liquid, no response to tilt, a new level with no slosh.
- The accessibility tree (`uiautomator dump`): the one-line summary and the
  pebble labels, including "over limit".
- Haptic calls reaching Android's vibrator service (`dumpsys
  vibrator_manager`): one tick per ring step, one pulse on filing and a
  different one on refusal.

### Checked only partly, or only by automated test

| What | How far it was checked | Why |
| --- | --- | --- |
| Haptic feel (ring ticks, success and refusal pulses) | Calls seen in the vibrator service log and asserted in widget tests | An emulator cannot be felt |
| Tilt by hand | Emulator sensor values only | No physical phone |
| Screen reader summary and pebble labels | Read from the accessibility tree, not heard through TalkBack | TalkBack was not set up on the emulator |
| Sustained slow frames switch to still water | Unit and widget tests (`trips after two seconds of 25 ms frames`, `sustained slow frames switch to still water…`); also happened unprompted in headless Chrome and cleared on reload | Slow frames cannot be produced on demand on the emulator |
| Note stored on the entry, and the default note | Typed and filed on the emulator; the stored value only by widget tests (`a typed note is stored on the entry`, `no note stores the category name`) | No screen shows an entry's note yet |
| Exactly "2.4 s" in the toast; the exact medians of the spec example | Widget and unit tests with a fake clock; on the emulator the times shown were plausible | Taps cannot be timed that precisely through adb |
| Entries from another month; exactly half; last day of the month; near and at a category limit; ten ₹37 entries; ₹1,50,000 | Unit tests in `test/budget/` | These states cannot be reached from the screens |
| Pebble positions the same on different days | Same positions seen across many openings in one day | The date cannot be changed in the app |
| Frame rate | 60 fps on the emulator's readout | Says little about a real phone |

### Found and fixed during this pass

- A pull-down sometimes did nothing (about one in five with `adb shell input
  swipe`). The Vessel's scroll view came out 1e-13 pixels taller than the
  screen, so an upward wobble of under a pixel as the finger lifted counted as
  scrolling and threw the pull away. `lib/home/pull_to_log.dart` now measures
  the pull from the finger's position and allows for rounding; coming most of
  the way back up now calls the pull off, as the droplet shows. Two tests
  added in `test/home/pull_to_log_test.dart`. Thirty pulls in a row opened
  afterwards.

### Known and left as they are

- A drag that starts within about 10 logical pixels below the status bar is
  taken by Android's notification shade. The handle is below that strip.
- During a pull-down Android's overscroll stretch moves the figures and
  pebbles down a little (up to about 20 logical pixels at the bottom on a long
  pull). The liquid does not move with them.
- The "Timings" label sits about 3 logical pixels lower than "Pull down to
  log".
- After the toast goes at 10 seconds, a late tap where Undo was lands on the
  Timings control.

### Chrome compared with the emulator

Driven in headless Chrome at 500×757: home screen, handle, pull-down with the
mouse, pad, chips, ring, note, refusal, filing, Undo, income and the Timings
sheet all worked, and the liquid shader ran.

- No tilt and no haptics, as expected.
- Text renders slightly heavier than on Android.
- Buttons show a hover highlight under the mouse.
- Headless Chrome renders in software, and after a while the app dropped to
  still water (flat liquid) until the page was reloaded. This is the slow-frame
  fallback working; an ordinary Chrome window with a GPU was not checked.

### Release APK

```sh
flutter build apk --release
```

`build/app/outputs/flutter-apk/app-release.apk`, 48,625,387 bytes (48.6 MB).
It is signed with the debug key, which is enough for side-loading. On the
emulator it started on the home screen with the liquid moving, showed no
frame-rate readout, and logged an expense.

To install it on an Android phone with USB debugging on:

```sh
adb install build/app/outputs/flutter-apk/app-release.apk
```
