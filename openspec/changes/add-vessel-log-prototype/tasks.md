# Tasks

## 1. Project setup

- [x] 1.1 Confirm the git repository at the project root (run `git init` if absent); verify `git status` lists the three source documents and `openspec/` as untracked
- [x] 1.2 Run `flutter create --project-name tide --platforms android,ios,web .` at the project root without touching the existing documents, and make sure the generated `.gitignore` is in place; verify `flutter analyze` reports no issues, the generated `flutter test` passes, and `git status` shows no build output or `.dart_tool`
- [x] 1.3 Add `flutter_riverpod` and `sensors_plus` with `flutter pub add`; verify `flutter pub get` succeeds and `flutter analyze` still reports no issues
- [x] 1.4 Start the `Pixel_7_API_36` emulator and run the app on it, then run it in Chrome; verify the default app appears on both and a hot reload of a text change shows up on the emulator
- [x] 1.5 Build a throwaway check screen with a `CustomPaint` running a simple animated fragment shader, a live accelerometer reading from `sensors_plus`, and a button that calls `HapticFeedback`; verify on the emulator that the shader animates, the reading changes when the emulator's virtual accelerometer is moved, and the button press raises no error, and note in the report how the shader behaves in Chrome
- [x] 1.6 Write a `README.md` with the commands to fetch packages, start the emulator, run on the emulator and in Chrome, run tests and analyse; verify each command works as written

## 2. Budget status logic

- [x] 2.1 Define the entry, category and budget types with amounts as integer paise, plus a rupee formatter using Indian digit grouping; verify unit tests cover `₹1,50,000`, `₹0`, a negative amount and ten ₹37 entries summing exactly
- [x] 2.2 Implement monthly position (amount available, amount remaining) limited to entries in the given calendar month; verify unit tests cover the three "Monthly position" scenarios in the budget-status spec
- [x] 2.3 Implement fill level and status band with mood label; verify unit tests cover every scenario under "Fill level" and "Status band", including exactly 0.5 and exactly ₹0 remaining
- [x] 2.4 Implement safe to spend today from the amount remaining and the date; verify unit tests cover 5 October, the last day of a month and an overspent month
- [x] 2.5 Implement category spend, share of limit and the near and over flags; verify unit tests cover every scenario under "Category position"
- [x] 2.6 Create the Riverpod state with an injectable clock, seed data (₹30,000 budget, six categories, the prototype's twelve entries re-dated into the current month) and actions to add and remove an entry; verify a unit test shows the seeded state yields ₹13,601 remaining and that adding then removing an entry restores it

## 3. Vessel home screen (static)

- [x] 3.1 Add the Bricolage Grotesque and DM Sans font files with their licence files under `assets/fonts`, declare them in `pubspec.yaml`, and define the colour tokens and text styles from design.md; verify on the emulator that both fonts render and that `flutter analyze` reports no issues
- [x] 3.2 Build the home widget as a `Stack` with the Vessel layer always present and an empty overlay slot for the log flow; verify on the emulator that the ink background fills the screen including behind the status bar
- [x] 3.3 Show the remaining amount, month, mood label, amount available, percentage full and safe-to-spend figure from the state; verify a widget test with the clock fixed at 5 October finds `₹13,601`, `Running lower`, `left of ₹30,000`, `45% full` and `Safe today: ₹503`
- [x] 3.4 Lay out the six category pebbles with name and spend, sized by share of limit with a 64-pixel minimum, and with the sunk offset and warning outline when over the limit; verify a widget test shows a 90% pebble larger than a 33% one and an over-limit pebble offset lower with the coral outline
- [x] 3.5 Add the `Semantics` summary for the vessel and labels for each pebble; verify a widget test finds a summary containing `45% left`, `₹13,601` and `safe today ₹503`, and an over-limit pebble label containing its name, spend, limit and `over limit`

## 4. Liquid rendering and motion

- [x] 4.1 Write the liquid fragment shader with inputs for time, fill height, surface lean, slosh amplitude and colour, drawing a wavy surface with a depth gradient, and paint it full-screen in its own `RepaintBoundary`; verify on the emulator that the liquid sits at about 45% of its range for the seeded data and the remaining amount stays fully readable
- [x] 4.2 Map fill level to liquid height with a floor and a ceiling; verify unit tests for the mapping at fill levels 0, 0.02, 0.5 and 1, and on the emulator that the text is never covered and a thin band is always visible
- [x] 4.3 Drive colour from the status band with a smooth transition; verify by adding entries that cross 0.5 and 0.25 on the emulator that the liquid goes teal, amber, coral and the mood label changes at the same moment
- [x] 4.4 Add the ticker-driven damped springs for fill height and slosh, triggered when the entries change, repainting through the painter's listenable; verify unit tests that each spring settles on its target within about one second, and on the emulator that adding an entry drains the liquid with a visible slosh
- [x] 4.5 Connect the accelerometer to the surface lean through a low-pass filter, subscribing only while the Vessel layer is on top; verify on the emulator that moving the virtual accelerometer leans the surface, and a widget test with a fake sensor source shows the subscription is cancelled while the overlay is open
- [x] 4.6 Build the overspent state with the hatched coral band, the negative amount and "Safe today: ₹0"; verify a widget test finds `−₹2,000`, `Below the line` and `Safe today: ₹0` when overspent by ₹2,000, and that adding income brings back the normal state
- [x] 4.7 Add the frame-time monitor, the still-water flag and the debug-only frame-rate readout, and set the flag from the platform's reduce-motion setting; verify a widget test with `disableAnimations` on shows the still-water painter while the level still updates, and a unit test shows the monitor trips after two seconds of 25 ms frames

## 5. Log flow

- [x] 5.1 Add the handle and the pull-down drag with the following droplet, starting below the top safe-area inset; verify widget tests that a 100-pixel drag opens the overlay, a 40-pixel drag does not, and tapping the handle opens it
- [x] 5.2 Build the log flow shell: Spend and Income switch, Cancel, the amount display starting at ₹0, and the amount bounds; verify a widget test that Cancel returns to the Vessel with the state unchanged, and unit tests for clamping at ₹0 and ₹9,99,999
- [x] 5.3 Build the number pad with digits and delete, where the first digit replaces the previous amount; verify unit tests that typing 3 then 7 gives ₹37 and delete on ₹1,850 gives ₹185, and a widget test that tapping the keys updates the displayed amount
- [x] 5.4 Build the amount ring with rotation tracking, the three speed-based step sizes and a haptic tick per step; verify unit tests that slow, medium and fast turns step by ₹10, ₹100 and ₹1,000 and anticlockwise lowers the amount, a widget test that one haptic call fires per step, and on the emulator that the ring turns under a drag
- [x] 5.5 Add the Ring and Pad switch that remembers the last choice for the session; verify a widget test that reopening the log flow shows the method used last time
- [x] 5.6 Implement frequent-amount chips (top five expense amounts, ties to the most recent) and show them above the ring or pad; verify a unit test for ordering and tie-breaking, and a widget test that tapping a chip sets the amount
- [x] 5.7 Build the fixed pebble grid and filing on tap, with the default note and the refusal when the amount is ₹0; verify widget tests that tapping Food at ₹250 returns to the Vessel with ₹250 less remaining and "Logged ₹250 to Food", and that tapping at ₹0 keeps the overlay open with a "set an amount first" message
- [x] 5.8 Add the collapsed note field; verify a widget test that a typed note is stored on the entry and an empty one stores the category name
- [x] 5.9 Build income mode with the six sources; verify a widget test that adding ₹5,000 from Freelance raises both the amount available and the amount remaining by ₹5,000 and shows "Added ₹5,000 from Freelance"
- [x] 5.10 Build the confirmation toast with a 10-second Undo that applies to the latest entry only, plus success and refusal haptics; verify widget tests with a fake clock that Undo at 4 seconds restores the amount remaining, that the button is gone after 10 seconds, that a second entry's Undo leaves the first in place, and that the success and refusal haptic calls fire

## 6. Time-to-log measurement

- [x] 6.1 Record open and filed timestamps and the last-used amount method for each expense, drop the record when the entry is undone, and compute count and median per method and overall; verify a unit test reproduces the "Median per method" scenario (pad 2.6 s, ring 4.0 s, overall 3.0 s) and the undo case
- [x] 6.2 Show the elapsed time in the confirmation toast; verify a widget test with a fake clock that an expense filed 2.4 seconds after opening shows `2.4 s`
- [x] 6.3 Add the "Timings" control on the home screen and its summary sheet with a clear action, labelled as a test instrument; verify a widget test that the sheet lists pad, ring, chips and overall, and that clearing zeroes the counts without removing entries

## 7. End-to-end check

- [x] 7.1 Run `flutter analyze` and `flutter test`; verify both finish with no issues or failures
- [x] 7.2 Walk through every scenario in the three specs on the Android emulator and note any that fail; verify each one passes or has a fix applied and re-checked, and list the scenarios that could only be checked partly (haptic feel, tilt by hand) in `README.md`
- [x] 7.3 Run the app in Chrome and check the Vessel, the log flow and filing; verify they work, and record in `README.md` anything that differs from the emulator
- [x] 7.4 Build a release APK with `flutter build apk --release`; verify the build succeeds and record the file path and size in `README.md` so it can be installed on a borrowed Android phone
- [ ] 7.5 Clear the timings and log at least ten expenses with each of the three methods on the emulator; verify the summary shows a median for each method, and record the three medians in `README.md` marked as emulator figures that do not settle the 3-second target
