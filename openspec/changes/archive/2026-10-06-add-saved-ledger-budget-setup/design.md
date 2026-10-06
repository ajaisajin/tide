# Design

## Context

See proposal.md for motivation. What exists and constrains the approach:

- The app is Flutter 3.44 with Riverpod 3. All data sits in one synchronous notifier, `BudgetNotifier` in `lib/state/budget_state.dart`, built from `seedEntries(now)` with a single `budgetMinor`. Screens read `budgetSnapshotProvider`; the log flow calls `addExpense`, `addIncome` and `removeEntry`, which return immediately.
- The budget maths in `lib/budget/` is pure Dart and takes a budget, entries, categories and a date. It needs no change to compute figures.
- 258 tests exist. Most pump the home screen through `test/support/pump_home.dart` and rely on the seeded month.
- A `TIDE_SCENARIO` compile-time flag (`lib/dev/scenario.dart`) starts the app in chosen states for visual checks.
- The technical specification sets SQLite through Drift, SQLCipher-style AES-256 with the key in Keychain or Keystore, integer paise, device-generated UUID v7 ids, soft deletes and UTC timestamps.
- Package check on this machine: `drift` 2.35.1, `drift_flutter` 0.3.1, `sqlite3` 3.5.2 and `flutter_secure_storage` 11.2.0 resolve. `sqlcipher_flutter_libs` and `sqlite3_flutter_libs` resolve only to versions tagged end-of-life, so encryption has to come from the `sqlite3` package's own build configuration. How exactly that is switched on in this version has not been tried yet.
- `android/app/src/main/AndroidManifest.xml` sets no backup attributes, so Android's automatic backup is on by default.
- Development is on Linux with an Android emulator and Chrome. iOS cannot be built here.

## Goals / Non-Goals

**Goals:**

- Real, saved, encrypted data on Android, with the same code path ready for iOS.
- Keep every screen and the budget maths reading state synchronously, so this change does not ripple through the widget tree.
- Keep the existing test suite meaningful with little rewriting.
- A database shape the later sync change can extend without rewriting rows.

**Non-Goals:**

- Sync columns that need a design of their own (`version`, hybrid logical clock, `user_id`).
- Purging soft-deleted rows.
- Saved data in Chrome.
- Verifying anything on iOS.
- A general settings screen. The budget screen is reached from the home screen's budget line only.

## Decisions

### 1. A store interface with two implementations

A `LedgerStore` interface in `lib/storage/` exposes the reads and writes the app needs: load a month's entries, insert an entry, soft-delete an entry, frequent expense amounts, load and save categories, effective budget for a month, set a month's budget, load and save the profile (income). Two implementations:

- `DriftLedgerStore`: the encrypted database, used on Android and iOS.
- `MemoryLedgerStore`: used by tests, by Chrome, and by `TIDE_SCENARIO` builds, optionally pre-loaded with the sample month.

One shared contract test suite runs against both, so the in-memory one cannot drift from the real one.

- *Drift everywhere including web*: Drift's web support needs a WebAssembly build and a worker file, and browser storage cannot meet the encryption requirement anyway.
- *No interface, Drift called directly from state*: every widget test would need a database.

### 2. Drift on an encrypted SQLite build, proven first

Drift is the technical specification's choice and gives typed queries and migrations. Encryption uses the `sqlite3` package's encrypted build with an AES-256 scheme selected explicitly, because some encrypted SQLite builds default to a different cipher. The end-of-life helper packages are not used.

Because the switch for this is untested here, the first task group is a spike: an encrypted database opened on the emulator with a key, shown to be unreadable without it, and the unit-test story on the Linux host settled (tests need a SQLite library on the host; encryption is not needed there). If AES-256 cannot be had from the current packages, work stops and the options go back to the developer.

Outcome of the spike (task group 1), which the store is built on:

- The build setting `hooks: user_defines: sqlite3: source: sqlite3mc` in `pubspec.yaml` bundles SQLite3 Multiple Ciphers. Its default cipher is ChaCha20, so every open sets `PRAGMA cipher = 'sqlcipher'` before the key. That scheme is AES-256-CBC with an HMAC-SHA512 tag per page.
- `PRAGMA legacy = 4` is set as well, so the whole file header is encrypted and the file is compatible with standard SQLCipher 4 tools. This was confirmed on the Linux host and is re-confirmed on the emulator in task 4.3. It has to be fixed before the first real database exists, because changing it later means re-encrypting.
- The key is passed as 32 raw bytes in hex, with no passphrase stretching.
- A missing or wrong key does not fail when the key is set. It fails on the first statement with SQLite error 26, "file is not a database". That error is how the "cannot be opened" case is detected.
- `drift_flutter` is not used. It pulls the two end-of-life packages into the lockfile as empty stubs; opening the database directly with Drift's `NativeDatabase` and `path_provider` avoids them for about ten lines of code.
- Drift tests run on the Linux host under `flutter test`, because the same setting bundles the library for the host.
- The first build after a clean checkout downloads the native library, so it needs network access.

- *Encrypting values in application code*: slow, breaks queries on amounts and dates, and leaks structure.
- *An unencrypted database now, encryption later*: converting a live database is harder than starting encrypted, and the BRD treats this as a launch requirement.

### 3. Key handling

On first open the app generates 32 random bytes with a secure random source and stores them through `flutter_secure_storage` (Android Keystore, iOS Keychain). Later opens read the key from there. The key is never logged or written elsewhere. If the database file exists but the key is missing or wrong, that is the "cannot be opened" case in the spec: the file is left alone.

### 4. Schema, version 1

| Table | Columns |
| --- | --- |
| `entries` | `id` (UUID v7 text, primary key), `type`, `amount_minor`, `currency` (default `INR`), `category_id` (nullable), `note`, `occurred_at`, `source`, `created_at`, `updated_at`, `deleted` |
| `categories` | `id`, `name`, `color`, `monthly_limit_minor`, `sort_order`, `created_at`, `updated_at`, `deleted` |
| `budgets` | `month` (`YYYY-MM`, primary key), `total_minor`, `created_at`, `updated_at` |
| `profile` | single row: `monthly_income_minor`, `home_currency` |

Indexes on `entries(occurred_at)` and `entries(category_id)`. All timestamps are UTC milliseconds. This follows the technical specification's tables, minus the sync-only columns. Drift's schema export is switched on and a version-1 snapshot is committed, so the first migration can be tested when it comes. Generated Drift code is committed, so a normal build does not need the code generator.

UUID v7 is generated by a small hand-written function (timestamp plus secure random bits), which avoids a dependency for about twenty lines.

### 5. State stays synchronous; loading happens before the first frame

`main()` opens the store and loads the starting data before `runApp`, then passes both into the `ProviderScope` as overrides. `BudgetNotifier` builds its state from that loaded data instead of from the seed. Every existing `ref.watch` keeps working, with no loading states inside screens.

While this runs, the platform's launch screen shows the ink background, which satisfies "only its background". A returning user's first Flutter frame is the home screen; a new user's is setup.

If opening fails, `main()` runs a small error screen with Retry, which re-runs the same start-up. Nothing in that path creates, deletes or overwrites the database file.

- *`AsyncNotifier` and `AsyncValue` throughout*: correct but touches every consumer and most tests for no user-visible gain.

### 6. Only the current month is held in memory

State holds the current month's entries, the categories, the effective budget and the income. The frequent-amount chips come from an aggregate query over all expenses, cached and refreshed after each write. Start-up time then does not grow with the age of the ledger.

### 7. Writes are awaited, then state changes

`addExpense`, `addIncome` and `removeEntry` become asynchronous: they write to the store, and only when that succeeds do they update state. The log flow awaits filing before closing and showing the confirmation, ignores further taps while a save is in flight, and on failure stays open with a message. Undo awaits the soft delete before restoring the figures.

- *Update the screen first and save in the background*: feels instant, but a crash between the two loses an entry the user was told was logged.

### 8. Undo is a soft delete

Undo sets `deleted` and `updated_at` on the row. Reads ignore deleted rows. Rows are kept because the sync change will need to tell other devices about deletions.

### 9. Budgets: one row per month, carried forward at read time

The effective budget for a month is that month's row if there is one, otherwise the row with the greatest earlier month. Nothing is written when a month begins. Changing the budget writes or updates the current month's row only.

Default category limits are a pure function of the budget (shares, rounded down to ₹100, floor of ₹100), applied once when setup completes.

### 10. The calendar is watched

A small "today" notifier holds the current local date. It refreshes when the app returns to the foreground and from a timer set for the next local midnight. When the day changes, the snapshot recomputes, which also corrects safe-to-spend, which today goes stale overnight. When the month changes, the month's entries and effective budget are reloaded from the store and state is replaced.

Entry instants are stored in UTC and converted to local time when read. A month's query bounds are the local month's first and last instants converted to UTC.

### 11. Setup and budget screens share one widget

A `BudgetVessel` widget reuses the Vessel's liquid painter and motion, with the level driven by a vertical drag instead of by spending. Level maps to budget as a share of income, snapped to the step size, with a haptic tick per step. Tapping the amount opens the existing number pad for exact entry. The same widget carries `Semantics` with increase and decrease actions.

- **Setup screen** (`lib/setup/`): income first (number pad), then the vessel, then Confirm.
- **Budget screen**: the same vessel pre-filled, an income row, and a list of the six category limits, each editable with the pad, with the total and the over-budget note. Save and Cancel.

The home screen's budget line ("left of ₹30,000") becomes a button that opens the budget screen in the existing overlay slot.

### 12. Which screen shows

A root widget chooses between setup and home from a `setupComplete` flag in state, true when a budget row exists. There is still no router.

### 13. Keeping the database out of backups

- **Android**: `android:allowBackup="false"` plus data-extraction rules that exclude the app's data from cloud backup and device transfer on Android 12 and later. The app has no other data worth backing up yet.
- **iOS**: the database file is flagged as excluded from backup through a small platform call. This is written but cannot be compiled or checked on this machine, and is recorded as unverified.

Cloud backup of the user's data is the job of the later sync change.

### 14. Sample data and development scenarios

The seeded month leaves the normal app. `TIDE_SCENARIO` builds use `MemoryLedgerStore`, so scenario data can never be written into a real database. A `demo` scenario reproduces the old seeded app. Tests keep the seeded month through `pump_home.dart`, which now provides a pre-loaded `MemoryLedgerStore`.

### 15. Measuring the speed targets

- **Save time**: an on-device integration test loads 2,000 entries into the encrypted store, performs 20 saves and reports the median.
- **Cold start**: the app logs the time from process start to the first home-screen frame in profile mode; the figure is read from `adb` over ten launches with 2,000 entries stored.

Both run on the emulator, so they show the code is not grossly slow, not that the BRD's reference phone meets the target.

## Risks / Trade-offs

- [AES-256 cannot be enabled with the current `sqlite3` package] → The spike in task group 1 finds out before anything is built on it. Stop and return to the developer with options if so.
- [Unit tests cannot load SQLite on the Linux host] → Settled in the same spike. Fallback: contract tests for the Drift store run on the emulator only, and host tests use the in-memory store.
- [The secure-storage key is lost while the database file survives, for example after an app-data restore] → Backups are disabled so this should not arise. If it does, the app reports that data cannot be opened and leaves the file. There is deliberately no "start fresh" button in this change.
- [iOS backup exclusion and Keychain behaviour are unverified] → Recorded in the README. To be checked when an iOS build exists.
- [Awaited saves make filing feel slower] → The target is 100 ms; the log flow shows no spinner below that. Measured in task group 8.
- [Existing tests assume synchronous filing] → The in-memory store completes on the next microtask, so most tests need one extra pump at most.
- [Soft-deleted rows accumulate] → Negligible at personal scale. Purging belongs to the sync change.
- [Default limits (Bills 35%, Shopping 7%) differ slightly from the sample data's limits] → Only the `demo` scenario keeps the old limits.
- [Speed targets are measured on an emulator] → Stated as emulator figures in the README.

## Migration Plan

There is no saved data anywhere yet, so there is nothing to migrate. The first launch of this version creates schema version 1. Rollback is reinstalling the previous build; its in-memory data is unaffected by a leftover database file.

## Open Questions

- The four additional default categories for FR-09 and the layout for ten pebbles. Decided in the categories change.
- Whether a "start fresh" recovery should exist when data cannot be opened, and how it is guarded. Decided with app lock and settings.
- Whether monthly income should later feed insights or savings goals. Does not affect what is stored now.
