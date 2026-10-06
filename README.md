# Tide

Tide is a personal expense tracker whose home screen is a liquid "vessel":
the fuller it is, the more of the month's budget is left. It is a Flutter app,
developed on Linux and checked on the Android emulator and in Chrome.

On Android the app keeps its data in an encrypted ledger on the device. A new
install opens on setup (`lib/setup/`): the monthly income, then a vessel that
is dragged, or typed into, to choose how much of it is the month's budget.
From then on it opens on the Vessel (`lib/home/home_screen.dart`,
`lib/vessel/`). Tapping the underlined "left of ₹…" line there opens the
budget screen (`lib/budget_screen/`), where the budget, the income and each
category's limit can be changed. The old sample month (a ₹30,000 budget and
twelve entries) is now the `demo` scenario, described below.

**In Chrome nothing is saved.** The web build keeps the ledger in memory:
every visit, and every reload of the page, starts again at setup with an
empty ledger. There is no encrypted storage in the browser.

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

# Run the on-device tests (each needs an install with no ledger; see Tests)
flutter test integration_test/encrypted_ledger_test.dart -d emulator-5554
flutter test integration_test/save_speed_test.dart -d emulator-5554
```

Nothing needs generating before a build: the Drift code (`*.g.dart`) is
committed. It is regenerated with `dart run build_runner build` only after
the tables change; see [Code generation](#code-generation).

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

`TIDE_SCENARIO` starts the app on sample data, in a chosen state, so the
Vessel can be checked by eye. It works with `flutter run` and `flutter build`:

```sh
flutter run -d emulator-5554 --dart-define=TIDE_SCENARIO=demo
```

Names: `demo` (the sample month as it is: ₹30,000 budget, twelve expenses,
₹13,601 remaining on the 5th), `full`, `low`, `calm`, `coral`, `overspent`,
`overlimit`, and `cycle` (files and removes entries every four seconds). See
`lib/dev/scenario.dart`.

A scenario build runs on an in-memory ledger and never opens the saved one, so
sample data cannot reach a real database. Checked on the emulator: after
clearing the app's data and launching a `demo` build, the app's `files`
directory holds no `ledger` directory and no database file, while an ordinary
build creates `files/ledger/tide.sqlite` on first launch.

## Storage

The app reads and writes through the saved, encrypted ledger in
`lib/storage/`. `main()` opens it and loads the current month before the first
frame (`lib/state/start_up.dart`, `lib/state/ledger.dart`), so screens go on
reading state synchronously. Every write is awaited before the screen changes:
an entry is confirmed only once it is saved, and a save or an Undo that fails
changes nothing and says so. If saved data exists but cannot be opened, the
app shows an error screen with Retry and leaves the file as it is.

### What is in `lib/storage/`

| File | What it is |
| --- | --- |
| `ledger_store.dart` | `LedgerStore`, the interface the app reads and writes through, and `Profile` |
| `memory_ledger_store.dart` | `MemoryLedgerStore`: nothing saved; for tests, Chrome and development scenarios |
| `drift/tide_database.dart` (+ `.g.dart`) | The Drift tables, schema version 1 |
| `drift/drift_ledger_store.dart` | `DriftLedgerStore`, the interface over the database |
| `drift/encrypted_database.dart` | Opens the SQLite file with the cipher settings below |
| `ledger_key.dart` | The 32-byte key: created once, kept in secure storage |
| `open_ledger.dart` | `openLedger()`, the entry point on a device |
| `open_ledger_result.dart` | Its three outcomes, in a file the web can import |
| `platform_ledger.dart` | `openPlatformLedger()`: `openLedger()` on a device, an empty in-memory ledger on the web |
| `backup_exclusion.dart` | The iOS excluded-from-backup call (no-op elsewhere) |

`storage.dart` exports the parts that work everywhere. `device_ledger.dart`
exports those plus the encrypted store, which needs `dart:io` and native
SQLite and so cannot be imported in a web build.

The database is `<application support>/ledger/tide.sqlite`; on Android that is
`/data/user/0/app.tide.tide/files/ledger/tide.sqlite`.

### Packages

| Package | Version resolved |
| --- | --- |
| `drift` | 2.35.1 |
| `sqlite3` | 3.5.2 (bundles SQLite 3.53.4 as SQLite3 Multiple Ciphers 2.5.0) |
| `flutter_secure_storage` | 11.2.0 |
| `path_provider` | 2.1.6 |
| `drift_dev` (dev) | 2.35.1 |
| `build_runner` (dev) | 2.15.1 |
| `integration_test` (dev) | from the Flutter SDK |

`drift_flutter` is not used. It pulled `sqlcipher_flutter_libs` and
`sqlite3_flutter_libs` into `pubspec.lock` at end-of-life versions; neither is
in the lockfile now. The database is opened with Drift's own
`NativeDatabase.createInBackground` and a path from `path_provider`.

### Encryption configuration

Two parts, and both are needed.

1. **Build time.** `pubspec.yaml` selects the encrypted SQLite build through
   the `sqlite3` package's build hook:

   ```yaml
   hooks:
     user_defines:
       sqlite3:
         source: sqlite3mc
   ```

   The hook downloads a prebuilt, checksum-verified `libsqlite3mc.so` per
   architecture from the `sqlite3` package's GitHub release and bundles it. No
   NDK or CMake is involved. The first build after a clean checkout needs
   network access; the files are then cached under `.dart_tool/hooks_runner/`.

2. **Open time.** SQLite3 Multiple Ciphers defaults to ChaCha20, so the AES-256
   scheme is chosen on every open, before the key is given. This is
   `applyLedgerCipher` in `lib/storage/drift/encrypted_database.dart`, run as
   the `setup` callback of `NativeDatabase`:

   ```dart
   if (db.select('PRAGMA cipher').isEmpty) {
     throw StateError('SQLite was built without encryption');
   }
   db.execute("PRAGMA cipher = 'sqlcipher'");
   db.execute('PRAGMA legacy = 4');
   db.execute('PRAGMA key = "x\'$keyHex\'"'); // 64 hex digits = 32 bytes
   ```

   The `x'...'` form passes the 32 bytes as the raw AES key, with no
   passphrase stretching. A wrong or missing key does not fail in `setup`; it
   fails on the first statement that reads the file, with
   `SqliteException(26): file is not a database`.

**Cipher in effect:** the `sqlcipher` scheme at its version 4 settings, which is
AES-256 in CBC mode with a random IV and an HMAC-SHA512 tag per 4096-byte page.
`legacy = 4` uses SQLCipher 4's own file layout: the whole header is encrypted
(the file starts with a random salt) and the file is compatible with standard
SQLCipher 4 tools. These three settings are fixed for the life of a database
file. Changing any of them later means re-encrypting it.

### The key

On first open, 32 bytes from `Random.secure()` are saved through
`flutter_secure_storage` under the name `tide.ledger.key.v1`, as 64 hex
digits. Later opens read them back. The key is never logged and never put in
an error message.

On Android the plugin keeps the value in
`shared_prefs/FlutterSecureStorage.xml`, encrypted with AES-GCM under a key
that is itself wrapped by an RSA key held in the Android Keystore. So a file
does hold the ledger key, but only in a form the Keystore is needed to undo.
The plugin's `resetOnError` option is turned off: by default it erases
everything it holds when a value fails to decrypt, which would destroy the
ledger's only key after a passing Keystore fault.

### Opening, and what happens when it cannot

`openLedger()` returns one of three results and never throws:

- `LedgerOpened(store)`.
- `LedgerCannotBeOpened(reason)`: a database file exists but there is no key
  for it, or the stored key is not a key, or the file does not read with the
  key (wrong key, damaged, or not a database).
- `LedgerOpenFailed(error, stackTrace)`: anything else, such as secure storage
  reporting an error.

A key and a database file are created only when no database file exists. An
existing file that cannot be read is first tried read-only, and is never
written to, replaced, renamed or removed; no key is created for it.

### Schema

Version 1, in `lib/storage/drift/tide_database.dart`: tables `entries`,
`categories`, `budgets` and `profile`, with indexes on `entries(occurred_at)`
and `entries(category_id)`. Every timestamp is UTC milliseconds since the Unix
epoch. `profile` has an `id` column fixed at 1 to hold it to a single row.

A snapshot of each schema version is kept in `drift_schemas/tide/`, so the
first migration can be tested against version 1 when it comes.

### Code generation

```sh
# After changing Drift table or database classes
dart run build_runner build

# After changing schemaVersion: writes drift_schemas/tide/drift_schema_vN.json
# and, from version 2, migration tests under test/drift/
dart run drift_dev make-migrations
```

Both read `build.yaml`. The first run of `build_runner` takes about 45 seconds
here, later ones a few. Generated `*.g.dart` files and the schema snapshots are
committed, so an ordinary build needs neither command.

### Backups

Saved data stays on the device, because its key cannot leave it.

- **Android.** `AndroidManifest.xml` sets `android:allowBackup="false"`, and
  `res/xml/data_extraction_rules.xml` excludes every storage domain from both
  cloud backup and device-to-device transfer on Android 12 and later (where
  `allowBackup` alone no longer stops a transfer).
  `res/xml/full_backup_content.xml` says the same for Android 11 and earlier.
- **iOS. Written but not verified.** `ios/Runner/AppDelegate.swift` answers a
  method channel, `app.tide/backup`, by setting `isExcludedFromBackup` on a
  path; `openLedger()` calls it with the `ledger` directory. The Keychain item
  is stored as "after first unlock, this device only". None of this has been
  compiled or run: iOS cannot be built on this machine.

### Tests

Drift tests run on the Linux host under plain `flutter test`. The same build
hook bundles the Linux `libsqlite3mc.so` for the test run, so no system SQLite
and no emulator is needed.

- `test/storage/ledger_store_contract.dart` is one suite of the behaviour every
  store must have. It runs against `MemoryLedgerStore`, against
  `DriftLedgerStore` in memory, and against `DriftLedgerStore` on an encrypted
  file, so the in-memory store cannot drift from the real one.
- `test/storage/open_ledger_test.dart` covers each outcome of `openLedger()`
  with a fake key store and real encrypted files in a temporary directory,
  including that a file which cannot be opened is byte-for-byte unchanged.
- `test/storage/sqlite_host_test.dart` fails if the `hooks:` block is removed
  from `pubspec.yaml`.
- `test/support/failing_ledger_store.dart` is a store that throws on demand,
  and `test/support/fake_secret_store.dart` a key store held in memory.

Month boundaries: the tests that place 00:10 on 1 November in November and
23:50 on 31 October in October run in the time zone of the machine. This
machine is on Indian time, so here they exercise the real conversion for
UTC+05:30. On a machine in another zone they prove only that the conversion is
consistent in that zone; `test/budget/year_month_test.dart` also checks the
+05:30 arithmetic with fixed UTC instants, which holds anywhere. To force
Indian time: `TZ=Asia/Kolkata flutter test`.

The on-device test needs the emulator:

```sh
flutter test integration_test/encrypted_ledger_test.dart -d emulator-5554
```

It opens the ledger through `openLedger()` with the real secure storage, saves,
closes, reopens and reads back; runs the contract suite through the cipher;
then removes the stored key and checks the result and that the file is
untouched. It refuses to start if the install already has a ledger, and
`flutter test` uninstalls the app when it finishes, so reinstall the debug
build afterwards.

`integration_test/save_speed_test.dart` is run the same way and has the same
two rules. It measures the save time; see [Speed](#speed).

### What was confirmed on the emulator

Pixel 7, API 36, x86_64, debug build, 5 October 2026.

- `PRAGMA cipher` returned `sqlcipher`, with `legacy` 4, `legacy_page_size`
  4096, `hmac_use` 1, `hmac_algorithm` 2 (SHA512), `kdf_algorithm` 2 (SHA512)
  and `kdf_iter` 256000. On a connection with nothing set it returned
  `chacha20`.
- The second open reused the stored key and read back every entry, category,
  budget and the profile.
- Opening the file with no key, with the right key under the default cipher,
  and with the right key under `sqlcipher` without `legacy = 4` each failed
  with error 26.
- The file pulled with `adb exec-out run-as app.tide.tide cat` (40,960 bytes)
  did not contain `SQLite format 3`; its first 24 bytes were not the plain
  header; no note, category name, table name, `INR`, month key or amount
  appeared in it; its byte entropy was 7.996 bits per byte; and the stock
  `sqlite3` tool refused it with "file is not a database".
- The test searched every file under the app's data directory for the key as
  hex, as raw bytes and as base64, and for each half of it. No file held it.
- With the key removed from secure storage, and again with a different key in
  its place, `openLedger()` returned `LedgerCannotBeOpened`, created no key,
  and left the file's size, modification time and bytes unchanged. With the
  key put back, the data was all still there.
- `adb shell bmgr backupnow app.tide.tide` (backup enabled, local transport)
  answered "Backup is not allowed" for Tide, and `dumpsys package` no longer
  lists `ALLOW_BACKUP`. Before the manifest change the same command had
  attempted a backup. Device-to-device transfer cannot be exercised on one
  emulator; for that, only the rules file itself was checked.
- During the earlier spike, with `legacy` unset, a Python script using the
  `cryptography` package decrypted pulled pages with AES-256-CBC and the same
  32-byte key and verified each page's HMAC-SHA512 tag. That independent check
  has not been repeated for the `legacy = 4` layout.

Not checked: iOS (cannot be built here). The web build has no encrypted
storage to check: it keeps the ledger in memory and saves nothing.

## Speed

Both targets in the ledger-storage spec were measured on 6 October 2026, **on
the emulator only** (Pixel 7 image, API 36, x86_64, on an 8-thread Core
i5-1135G7 laptop). They show the code is not grossly slow. They say nothing
about the reference phone, which has not been measured.

| What | Target | Measured on the emulator |
| --- | --- | --- |
| Saving one entry, median of 20 saves with 2,000 entries stored | 100 ms | 3.0 to 3.5 ms across three runs (slowest single save 21.2 ms) |
| Cold start to the first home-screen frame, 2,020 entries stored, ten starts | 1.5 s | median 699 ms, worst 754 ms |

### Save time

```sh
flutter test integration_test/save_speed_test.dart -d emulator-5554
```

The test opens the real encrypted ledger with the real key store, completes
setup through the app's own state, loads 2,000 entries (100 in the current
month, 100 in each of the nineteen before), closes and reopens the ledger,
and then times 20 saves one after another. Each is timed from the call the
log flow makes when a pebble is tapped (`BudgetNotifier.addExpense`) to that
call returning, which is when the row is in the database. The touch itself
and the frame that follows are not in the figure. It prints lines starting
`TIDE_SPEED` and fails if the median is over 100 ms.

It is a debug build, as `flutter test` builds it. The three runs gave medians
of 3.5, 3.4 and 3.0 ms, with slowest saves of 21.2, 8.0 and 7.5 ms (the
slowest was the first save of its run each time). An emulator on a laptop SSD
writes far faster than a phone's flash, so the margin on a phone will be
smaller than this suggests.

### Cold start

A profile build logs one line when its first frame is on the screen
(`lib/dev/start_timing.dart`; debug and release builds log nothing):

```
TIDE_START home 699 ms
```

The time is from the start of the app's process (`/proc/self/stat`) to the
first frame having been drawn, and the word says what that frame showed
(`home`, `setup` or `error`). The ledger is opened and read before the first
frame, so that time is in the figure. The start time is counted in hundredths
of a second, and the method is only right on a device that has not slept
since it booted, which is true of the emulator.

The app has no code that fills a ledger. The 2,000 entries come from the
save-time test, built as an app of its own and told to leave its ledger
behind, with the profile build then installed over it (same package, same
debug signing key, so the data and its key stay):

```sh
flutter build apk --debug -t integration_test/save_speed_test.dart \
  --dart-define=TIDE_IT_KEEP_LEDGER=true
adb uninstall app.tide.tide
adb install build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n app.tide.tide/.MainActivity
adb logcat -d -s flutter | grep TIDE_SPEED     # wait for the line with KEPT

flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk

# One cold start; repeat ten times
adb shell am force-stop app.tide.tide
adb logcat -c
adb shell am start -W -n app.tide.tide/.MainActivity
adb logcat -d | grep -E "TIDE_START|Start proc.*app.tide"
```

That leaves 2,020 entries: the 2,000 and the 20 timed saves, 120 of them in
the current month.

The ten starts, in order: 700, 707, 698, 754, 703, 679, 692, 684, 710 and
684 ms. Median 699 ms, worst 754 ms. Two other readings of the same ten
starts agree with them: the gap between Android's own `Start proc` line and
the `TIDE_START` line in the log was within 10 ms of the logged figure each
time, and `am start -W` gave a `TotalTime` (which also counts the time before
the process exists) with a median of about 746 ms and a worst of 800 ms. Every
start was reported as `COLD`.

An earlier set of ten on the same data, before the launch screen fix below,
gave a median of 739 ms and a worst of 882 ms, and the very first start
after installing took 927 ms. All are under the target.

## Verification: saved ledger, setup and the budget screen

Checked on 6 October 2026 against the two specs in
`openspec/changes/add-saved-ledger-budget-setup/specs/` (monthly-budget and
ledger-storage).

**The app has still not been run on a physical phone, and never on iOS.**
Everything below was done on the Android emulator (Pixel 7 image, API 36)
driven with `adb shell input`, and in headless Chrome driven over the DevTools
Protocol. Unless a build is named, it was the debug build.

`flutter analyze`: no issues. `flutter test`: 599 tests pass. On the emulator,
`integration_test/encrypted_ledger_test.dart` passes (37 tests: the ledger
check and the whole store contract through the cipher) and so does
`integration_test/save_speed_test.dart`.

### Seen working on the emulator

Setup, from a fresh install:

- The app opens on setup, at the income pad showing ₹0 with Next dimmed.
- ₹45,000 typed and Next: the income is shown with Change beside it, and the
  vessel is offered, empty, with "Drag up to fill" and Confirm dimmed.
- Dragging the level to two thirds of the tank reads ₹30,000 with ₹15,000 set
  aside; dragging past the top stops at ₹45,000 with ₹0 set aside. The liquid
  is the shader liquid, drawn inside the tank with its surface at the right
  height (measured on the screenshots at two thirds, and at ₹28,750).
- Tapping the budget figure opens the pad. ₹50,000 and Done is refused with
  "Budget cannot be more than your income of ₹45,000"; ₹28,750 and Done is
  taken, with ₹16,250 set aside and the level moved to match.
- Force-stopping part-way through and opening again shows setup from the
  start, at ₹0.
- Confirm with ₹45,000 and ₹30,000: home shows ₹30,000, "left of ₹30,000",
  "100% full", every category at ₹0, and limits of ₹6,000, ₹10,500, ₹3,000,
  ₹2,100, ₹1,500 and ₹1,500. The income added nothing to the vessel.
- Two more fresh setups: a budget of ₹18,400 gave Food ₹3,600 and Shopping
  ₹1,200; a budget of ₹1,000 gave ₹200, ₹300 and four limits of ₹100.
- Large text and a small screen: font scale 1.5 and 2.0 at the Pixel 7's
  size, and 1.0, 1.5 and 2.0 at 720×1280 with density 320 (360×640 logical
  pixels), on the income pad, the vessel and the vessel's pad. Nothing
  overflowed or overlapped, and Flutter logged no overflow. At 360×640 with
  font scale 2.0 the tank is about 106 logical pixels tall, which is small
  but still drags; the page scrolls where it has to.

The budget screen:

- Tapping the budget line opens it with the saved income, the budget on the
  vessel and the six limits. The line answers a tap anywhere along its text,
  at its top and bottom edges. It is 41 logical pixels tall, a little under
  the 48 that Android suggests; the pill below it is not a control, so a tap
  that misses does nothing.
- Pull-down and the handle still open the log flow.
- Changing the budget and leaving by Cancel, and again by the system back
  button, left the home screen's figures as they were.
- With ₹13,601 left of ₹30,000 (Food at ₹2,330), saving a budget of ₹32,000
  and a Food limit of ₹8,000 showed ₹15,601, "left of ₹32,000" and Food at
  ₹2,330 of ₹8,000, with Bills' limit still ₹10,500.
- Limits totalling ₹36,000 against a budget of ₹32,000 showed "₹4,000 more
  than the budget", and Save still saved.
- Saving a budget of ₹15,000 with ₹16,399 spent showed the overspent state
  at −₹1,399.
- Changing the income to ₹6,000 on that screen and dragging moved the budget
  in steps of ₹100 (₹1,900, ₹2,000, ₹2,100, ₹2,200).
- Large text and the small screen, as for setup: the screen, the vessel's
  pad and a limit's pad. Nothing overflowed.

Saved data:

- ₹250 to Food, a force-stop within about half a second of the tap, and a
  relaunch: ₹29,750, with Food at ₹250. The same again for a second entry.
- ₹250 to Food, Undo, force-stop, relaunch: the entry was not there.
- The budget of ₹32,000 and Food's limit of ₹8,000 were still there after
  `adb reboot`.
- A returning user's launch, caught in ten screenshots taken across a cold
  start of the profile build with 2,020 entries: the launcher, the ink
  background, then the home screen. Setup was in none of them.
- The stored key taken away (the secure-storage file moved aside) and the app
  launched: "Tide's data could not be opened", with Retry. Setup was not
  shown. The database file's checksum was the same before the launch, after
  it, and after tapping Retry, and no new key was written. With the key put
  back the data was all there.
- The database file swapped for 40,960 random bytes and the app launched: the
  same screen, and the random file's checksum unchanged. With the real file
  put back while that screen was showing, Retry opened the home screen with
  the right figures.
- The app's own database file, pulled off the emulator after all of the
  above: no SQLite header, none of nine words and names searched for, 7.995
  bits of entropy per byte, and "file is not a database" from the `sqlite3`
  tool. The search of the app's files for the key is in the on-device test.
- `adb shell bmgr backupnow app.tide.tide`, with backup switched on and the
  local transport chosen: "Backup is not allowed".

The calendar (the emulator's clock set with `adb shell cmd alarm set-time`,
automatic time off, Indian time):

- On the home screen at 23:58:50 on 31 October with a budget of ₹15,000, left
  open: at 00:00 it showed November, ₹15,000 remaining and every category at
  ₹0, without being touched.
- Put in the background on 30 October and brought back on 2 November: it
  showed November.
- November's budget then set to ₹32,000: back in October, October's was
  still ₹15,000.
- An expense logged at 00:10 on 1 November counted in November and not in
  October; one logged at 23:50 on 31 October counted in October and not in
  November.

The earlier Vessel and log flow, from an empty ledger after setup: the first
expense by pull-down; teal at 67% ("Calm water"), amber at 37% ("Running
lower") and coral at 20% ("Nearly dry") with the label changing with the
colour; exactly ₹0; −₹2,000 with the hatched band and "Safe today: ₹0"; back
to ₹3,000 with ₹5,000 of income from Salary; the Timings sheet with seven pad
entries and their median; Undo. Nothing had regressed.

Haptics: `dumpsys vibrator_manager` showed the app's ticks arriving while the
level was dragged.

### Checked only partly, or only by automated test

| What | How far it was checked | Why |
| --- | --- | --- |
| A failed save records nothing and keeps the log flow open (and the same for Undo, setup and the budget screen) | Widget tests with a store that fails on demand (`test/log/`, `test/home/`, `test/setup/`, `test/budget_screen/`) | A write cannot be made to fail on the emulator from outside the app |
| The screen reader's increase action raises the budget by one step and announces it | Widget test (`test/setup/budget_vessel_test.dart`). On the emulator the accessibility tree (`uiautomator dump`) shows the vessel as a seek bar labelled "Budget vessel, ₹30,000 of ₹45,000 income, ₹15,000 set aside", and the label followed every change | TalkBack was not set up on the emulator, and adb cannot perform an accessibility action |
| The confirmation appears only after the entry is saved | Widget tests with a store that holds the write. On the emulator the app was stopped about half a second after the filing tap and the entry was there | The moment the toast appears cannot be caught through adb |
| The setup screen is never shown to a returning user, even for a frame | Widget test (`test/home/launch_test.dart`), plus the ten screenshots above | Screenshots are about a quarter of a second apart |
| One haptic tick for each step of the drag | Widget test. On the emulator ticks arrived during a drag but were not counted against steps | An emulator cannot be felt, and Android drops ticks that arrive faster than it can play them |
| Save time and cold start on a phone | Emulator figures only; see [Speed](#speed) | No physical phone |
| Device-to-device transfer leaves the ledger out | The rules file only | It needs two devices |
| The key is in no ordinary file | The on-device test's search of the app's data directory | The release build's files cannot be read with adb |
| Small income: steps of ₹100 | Seen on the budget screen with the income changed to ₹6,000, not in setup itself | Same widget and rules; setup with ₹6,000 was not run separately |

Everything else in the two specs was seen on the emulator as listed above.

### Found and fixed during this pass

- **The launch screen was white with the Flutter logo.** The spec asks for
  only the app's background while saved data is read. The Android launch
  theme was still the template's. It is now the ink background with no icon,
  on Android 12 and later as well (`android/app/src/main/res/values*/`,
  `drawable*/launch_background.xml`, `drawable/launch_no_icon.xml`). Seen on
  the emulator afterwards, with Android in its light theme; the dark-theme
  resources say the same but were not looked at. The iOS launch screen's colour was changed to match
  in `LaunchScreen.storyboard`, which is unverified like the rest of iOS.
- **In setup on a small screen, the vessel's number pad was cut short.** At
  360×640 the pad was squeezed into the room the tank had had, so even at the
  default text size the 0 key was clipped and the keys had to be scrolled
  inside a window about 100 logical pixels tall. The setup screen now asks
  for the pad's full height while it is open, and the whole page scrolls
  instead (`lib/setup/setup_screen.dart`). Test added: "360x640: with the
  budget pad open the page scrolls and the whole pad is laid out…".
- **The budget screen scrolled under the status bar.** Scrolled up, Cancel
  and Save showed through the clock and could not be tapped there, because
  Android keeps touches in that strip. The scroll view now stops at the
  system bars (`lib/budget_screen/budget_screen.dart`). Test added: "scrolled
  content stays between the system bars…".

### Known and left as they are

- Changing the device's clock by hand while the app is open is not noticed
  until the app next comes to the foreground: the timer for midnight was set
  from the old time. A real midnight, and coming back to the app, both work.
- On the budget screen, Cancel and Save scroll away with the rest. They are
  back at the top of the scroll.
- With large text the line under the budget wraps, leaving its "·" at the
  end of the first line.
- The log flow cannot be opened by the handle while a confirmation is
  showing over it (about ten seconds); pull-down still works. This is the
  earlier design.

### Chrome

`flutter build web`, served locally and driven in headless Chrome at 500×828.
Setup (income, drag to ₹30,000, ₹50,000 refused, a typed budget, Confirm),
logging by pad and by chip, Undo, pull-down, and the budget screen (a Food
limit of ₹8,000 and a budget dragged to ₹32,000, saved, with home showing
₹31,750 "left of ₹32,000") all worked. Reloading the page went back to setup
at ₹0: **nothing is saved in the browser.** As before, headless Chrome renders
in software and the liquid dropped to still water after a while; an ordinary
Chrome window with a GPU was not checked.

### Not verified on iOS

iOS cannot be built on this machine, so nothing has been compiled or run
there. In particular:

- that the app builds, and that the encrypted SQLite library is bundled;
- the Keychain item holding the key ("after first unlock, this device only");
- the excluded-from-backup flag on the ledger directory
  (`ios/Runner/AppDelegate.swift`, channel `app.tide/backup`);
- the launch screen's ink background;
- setup, the budget screen, haptics and everything else above.

## Verification: the Vessel and log flow prototype

Checked on 5 October 2026 by an independent pass over the three specs in
`openspec/changes/add-vessel-log-prototype/specs/`. The figures in this
section are from that day, when the app still started on the sample month.

**The app has not been run on a physical phone.** Everything below was done on
the Android emulator (Pixel 7, API 36) driven with `adb shell input`, and in
headless Chrome driven over the DevTools Protocol. The 3-second logging target
is therefore not yet tested, and no time-to-log medians are recorded here.

`flutter analyze`: no issues. `flutter test`: 258 tests passed at the time.

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

`build/app/outputs/flutter-apk/app-release.apk`, 57,727,517 bytes (57.7 MB)
on 6 October 2026. It is signed with the debug key, which is enough for
side-loading. On a clean emulator install (`adb uninstall app.tide.tide`
first) it opened on setup; with setup completed it showed the home screen with
the liquid moving and no frame-rate readout, logged an expense, and still had
it after a force-stop. It logs no `TIDE_START` line.

To install it on an Android phone with USB debugging on:

```sh
adb install build/app/outputs/flutter-apk/app-release.apk
```
