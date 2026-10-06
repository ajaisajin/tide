# Proposal

## Why

Tide forgets everything when it closes: entries live in memory and every launch starts from the same sample month with a fixed ₹30,000 budget. Nobody can use it for their own money until entries are saved and the budget is theirs. This change covers BRD requirements FR-02 (set income and budget by filling the vessel), FR-11 (monthly budget, per-category limits, safe to spend), NFR-02 (start-up and save speed) and the storage part of NFR-04 (encryption at rest).

## What Changes

- Save entries, categories, the budget and the user's monthly income in an encrypted database on the device, so they are still there after the app is closed, killed or the phone restarts.
- Replace the sample data with a real first run: a new install opens on a setup screen, and after setup the Vessel starts empty with the six default categories at ₹0 spent. **BREAKING** for the current build's behaviour: the seeded October entries no longer appear in the normal app. They remain available only as a development scenario.
- Add the setup screen from FR-02: one screen where the user gives their monthly income and then drags the water level up to set how much of it is the month's budget, with a typed alternative to the drag.
- Give every category a default limit scaled to the chosen budget, and let the user change each category's limit.
- Let the user change the budget and income later from the home screen.
- Keep one budget per calendar month. When a new month begins, the previous month's budget carries forward, and the home screen's figures switch to the new month without restarting the app.
- Make an entry durable before it is confirmed: filing waits for the save (target 100 ms or less), and a failed save tells the user and records nothing.
- Make Undo remove the saved entry, not only the one in memory.
- Show the home screen within 1.5 seconds of a cold start, with no flash of the setup screen for a returning user.
- Keep the database out of Android's automatic cloud backup, because the encryption key stays on the device and a restored copy could not be opened.

Assumptions recorded here because the BRD leaves them open:

- "Monthly income" is a reference figure used to size the budget during setup. It is not recorded as an income entry and does not add to the amount available.
- The six categories already in the app stay as the defaults. The BRD's ten default categories (FR-09) arrive with the categories change, because ten pebbles need a new layout on both the home screen and the log flow.
- In Chrome the app keeps its data in memory only, as today. Saved, encrypted storage is for Android and iOS.

Out of scope for this change: creating, renaming, recolouring or merging categories (FR-09, FR-10); editing or deleting past entries and browsing history (FR-14, FR-15); rollover of unspent money (FR-12); app lock and hide-amounts (FR-22); accounts, cloud sync and backup; saving the time-to-log test figures.

## Capabilities

### New Capabilities

- `monthly-budget`: how the user's income, monthly budget and category limits are set, changed and carried from one month to the next, including first-run setup by filling the vessel.
- `ledger-storage`: keeping the user's entries, categories and budget on the device: durability across restarts, encryption at rest, save and start-up speed, behaviour when saving or opening fails, and exclusion from device backup.

### Modified Capabilities

None. The requirements in `budget-status`, `vessel-home` and `expense-logging` from the change `add-vessel-log-prototype` are unchanged; this change supplies the budget and the storage they rely on. That earlier change is not yet archived, so the project has no main specs to modify.

## Impact

- **Code**: `lib/state/` (the budget state loads from and writes to storage; seed data moves behind the development scenario), `lib/budget/` (income, default category limits, per-month budgets), `lib/main.dart` (start-up decides between setup and home), `lib/log/` and `lib/state/confirmation_state.dart` (filing and Undo wait on storage), `lib/home/` (entry point to change the budget). New `lib/storage/` and `lib/setup/`. Existing tests that assume seeded data or synchronous filing need updating.
- **Dependencies**: `drift` 2.35, `sqlite3` 3.5 built with encryption, `flutter_secure_storage` 11 for the key, `path_provider`, and `drift_dev` with `build_runner` for code generation. The older `sqlcipher_flutter_libs` and `sqlite3_flutter_libs` packages are marked end-of-life and are not used.
- **Android**: backup rules in the manifest. **iOS**: the database file is marked as excluded from backup; not verified in this change because iOS cannot be built on this machine.
- **Technical specification**: followed for SQLite via Drift, encryption with the key in Keychain or Keystore, integer paise, device-generated UUID v7 ids, soft deletes and UTC timestamps. Its `version` and hybrid-logical-clock columns are left for the sync change.
- **Still unverified after this change**: the 1.5 second and 100 ms targets are measured on the emulator only, not on the BRD's reference phone.
