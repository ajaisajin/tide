# Tasks

## 1. Storage spike and dependencies

- [x] 1.1 Add `drift`, `drift_flutter`, `sqlite3`, `flutter_secure_storage` and `path_provider`, plus `drift_dev` and `build_runner` as dev dependencies, without using the end-of-life `sqlcipher_flutter_libs` or `sqlite3_flutter_libs`; verify `flutter pub get` succeeds and `flutter analyze` and the existing 258 tests still pass
- [x] 1.2 Configure the `sqlite3` package's encrypted build with an AES-256 scheme, following the installed version's own documentation, and write a throwaway check that opens a database with a 32-byte key on the Android emulator, writes a row, closes and reopens it; verify the row reads back with the key, opening without the key fails, and the pulled file (`adb exec-out run-as`) does not start with the standard SQLite header and contains no plain-text row value. If AES-256 cannot be enabled, stop and report the options to the developer
- [x] 1.3 Establish how Drift tests run on the Linux host (an unencrypted in-memory database is enough there); verify a one-table Drift test passes under `flutter test`, or record in `README.md` that Drift tests run on the emulator only and how
- [x] 1.4 Remove the throwaway check code and record the working encryption configuration and cipher in `README.md`; verify `flutter analyze` is clean and a release APK still builds

## 2. Budget rules (pure Dart)

- [x] 2.1 Add default category limits as a pure function of the budget (shares 20/35/10/7/5/5 percent, rounded down to ₹100, floor ₹100); verify unit tests cover every scenario under "Default category limits" in the monthly-budget spec
- [x] 2.2 Add effective-budget resolution over a set of month budgets (the month's own, else the most recent earlier one); verify unit tests cover both scenarios under "One budget per month, carried forward", a month earlier than any budget, and a year boundary
- [x] 2.3 Add the budget stepping rules for the vessel (level to budget by share of income, ₹500 steps or ₹100 below ₹10,000 income, clamped from ₹0 to income) and typed-budget validation (₹1 to income); verify unit tests cover the scenarios under "Setting the budget by filling the vessel" and "Typing the budget"
- [x] 2.4 Add income and limit amount rules (₹1 to ₹99,99,999) and the limits-total comparison with the budget; verify unit tests cover the bounds and the "₹4,000 more than the budget" case
- [x] 2.5 Add a UUID v7 generator and local-month to UTC bounds helpers; verify unit tests that ids are unique, time-ordered and correctly formatted, and that the bounds for October 2026 in Indian time place 00:10 on 1 November in November and 23:50 on 31 October in October

## 3. Store interface and in-memory store

- [x] 3.1 Define the `LedgerStore` interface in `lib/storage/` (month entries, insert, soft delete, frequent amounts, categories, effective and set budget, profile, has-budget check); verify `flutter analyze` is clean
- [x] 3.2 Implement `MemoryLedgerStore`, optionally pre-loaded with the sample month; verify a shared contract test suite passes against it, covering insert then read, soft-deleted entries not returned, month filtering at local month edges, frequent amounts ordering, budget carry-forward and profile round trip
- [x] 3.3 Add a store that fails on demand for tests; verify it can be made to throw on insert and on delete

## 4. Encrypted Drift store

- [x] 4.1 Define the Drift tables and indexes from design.md decision 4, generate the code, commit it, and enable schema export with the version-1 snapshot committed; verify `dart run build_runner build` completes and `flutter analyze` is clean
- [x] 4.2 Implement `DriftLedgerStore`; verify the same contract test suite from 3.2 passes against it (on the host or the emulator, as settled in 1.3)
- [x] 4.3 Implement key creation and retrieval through `flutter_secure_storage` and opening the database with it; verify on the emulator that a second launch reuses the same key, the key does not appear in any file under the app's data directory, and the database file is unreadable without it
- [x] 4.4 Implement the "cannot be opened" result: an existing database file with a missing or wrong key is reported as an error and left untouched; verify a test (or an emulator check, by clearing the secure storage entry) shows the error result and that the file's size and modification time are unchanged
- [x] 4.5 Exclude saved data from backup: `allowBackup="false"` and data-extraction rules on Android, and the excluded-from-backup flag on the iOS database file; verify on the emulator with `adb shell bmgr` that a backup run includes none of Tide's files, and record in `README.md` that the iOS part is written but unverified

## 5. State and start-up

- [x] 5.1 Load the store and starting data in `main()` before `runApp` and pass them in as provider overrides; build `BudgetNotifier` from the loaded data (current month's entries, categories, effective budget, income) instead of the seed; verify a widget test with a pre-loaded store shows the stored figures on the first frame
- [x] 5.2 Add the root widget that shows setup when no budget exists and home otherwise, and the error screen with Retry when the store cannot be opened; verify widget tests for all three cases, including that Retry leads to home once the store opens and that the setup screen is never built for a store that has a budget
- [x] 5.3 Make `addExpense`, `addIncome` and `removeEntry` await the store before changing state; verify unit tests that state changes only after the write completes and does not change when the store throws
- [x] 5.4 Update the log flow to await filing, ignore taps while a save is in flight, and on failure stay open with the amount intact and a "could not be saved" message; verify widget tests for success, for the failure scenario in the ledger-storage spec, and that a double tap records one entry
- [x] 5.5 Update Undo to await the soft delete; verify a widget test that after Undo the store no longer returns the entry, and that a failed delete leaves the entry and tells the user
- [x] 5.6 Serve the frequent-amount chips from the store's aggregate query, refreshed after each write; verify the existing chip tests pass and a test shows a newly frequent amount moving first after filing
- [x] 5.7 Add the "today" notifier (foreground resume and a timer to the next local midnight) and reload the month's entries and budget when the month changes; verify widget tests with a controllable clock for both scenarios under "Figures follow the calendar", and that safe-to-spend changes when only the day changes
- [x] 5.8 Move the sample month behind `TIDE_SCENARIO` using `MemoryLedgerStore`, add the `demo` scenario, use the in-memory store on web, and point `test/support/pump_home.dart` at a pre-loaded in-memory store; verify the whole existing test suite passes and a scenario build on the emulator creates no database file

## 6. Setup screen

- [x] 6.1 Build the `BudgetVessel` widget: the liquid painter with its level driven by a vertical drag, mapped to a budget with the stepping rules, a haptic tick per step, and live budget and set-aside figures; verify widget tests that a drag to two thirds with income ₹45,000 reads ₹30,000 and ₹15,000, that dragging past the top stops at the income, and that one haptic call fires per step
- [x] 6.2 Add typed entry: tapping the budget opens the number pad, a valid amount moves the level, and an amount above income is refused with a message; verify widget tests for ₹28,750 and for ₹50,000 against income ₹45,000
- [x] 6.3 Add `Semantics` to the vessel as an adjustable value with increase and decrease actions; verify a widget test that the increase action raises the budget by one step and the label carries the new amount
- [x] 6.4 Build the setup screen: income with the number pad, then the vessel, then Confirm, disabled until income and a budget of at least ₹1 are set; verify widget tests for "Income entered", "No budget yet" and that nothing is saved before Confirm
- [x] 6.5 Complete setup: save income, the current month's budget and the default category limits, then show the home screen; verify a widget test for the "Confirming" scenario (₹30,000 remaining, "100% full", every category ₹0, limits as in the spec) and that the store holds all three
- [x] 6.6 Check the setup screen on the emulator from a fresh install, including the drag, the typed entry, large text and a small screen; verify by screenshots that nothing overflows or overlaps, and that closing the app mid-setup and reopening shows setup again

## 7. Budget screen

- [x] 7.1 Make the home screen's budget line a button with a semantic label that opens the budget screen in the overlay slot; verify a widget test that tapping it opens the screen showing the saved income, budget and six limits, and that the existing pull-down and handle still open the log flow
- [x] 7.2 Build the budget screen with the pre-filled vessel, an editable income row, Save and Cancel; verify widget tests for "Raising the budget mid-month", "Lowering the budget below what is spent", "Leaving without saving", and that the system back button behaves as Cancel
- [x] 7.3 Add the category limits list, each editable with the number pad within ₹1 to ₹99,99,999, with the running total and the over-budget note; verify widget tests for "Raising a limit", "Limits add up to more than the budget", and "Category limits untouched" when only the budget changes
- [x] 7.4 Save budget, income and limits through the store with the same failure handling as filing; verify widget tests that a failed save changes nothing and says so, and that saved values survive rebuilding the app on the same store

## 8. Performance, end-to-end check and documentation

- [x] 8.1 Write the on-device integration test that loads 2,000 entries into the encrypted store and reports the median of 20 saves; verify it runs on the emulator and record the median in `README.md` against the 100 ms target, marked as an emulator figure
- [x] 8.2 Log the time from process start to the first home-screen frame in profile mode and measure ten cold starts with 2,000 entries stored; verify the median and worst case are recorded in `README.md` against the 1.5 second target, marked as emulator figures
- [x] 8.3 Run `flutter analyze` and `flutter test`; verify both finish with no issues or failures
- [x] 8.4 Walk through every scenario in the monthly-budget and ledger-storage specs on the Android emulator, including force-stop and relaunch, an emulator reboot, Undo then relaunch, and changing the emulator's date across a month end; verify each passes or has a fix applied and re-checked, and list in `README.md` any that could only be checked by automated test
- [x] 8.5 Re-check the earlier Vessel and log-flow behaviour on the emulator from an empty ledger (first expense, crossing colour bands, overspent and back, timings sheet); verify nothing has regressed
- [x] 8.6 Run the app in Chrome and check setup, logging and the budget screen; verify they work and that `README.md` states data is not saved in the browser
- [x] 8.7 Build a release APK and update `README.md` (commands, the code-generation step, the `demo` scenario, what is unverified on iOS); verify the APK installs and launches into setup on a clean emulator install
