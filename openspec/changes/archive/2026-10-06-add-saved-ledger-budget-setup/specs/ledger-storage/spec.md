# Spec Delta

## Purpose

Keeps a person's entries, categories, budgets and income on their device so the app can be trusted with real money records: nothing is lost when the app closes, nothing is readable off the device without its key, and saving and starting stay fast.

## ADDED Requirements

### Requirement: Data survives the app closing
Entries, categories with their limits, each month's budget and the monthly income SHALL still be present, unchanged, after the app is closed, force-stopped or the device is restarted.

#### Scenario: Reopening after a force-stop
- **WHEN** the user logs ₹250 to Food, the app is force-stopped and opened again
- **THEN** the home screen shows the same remaining amount as before the stop and Food includes the ₹250

#### Scenario: Budget and limits kept
- **WHEN** the user sets a budget of ₹32,000 and a Food limit of ₹8,000, then restarts the device
- **THEN** the budget is ₹32,000 and Food's limit is ₹8,000

### Requirement: An entry is saved before it is confirmed
The app SHALL show the confirmation for an entry only after the entry has been saved to the device.

#### Scenario: Stop immediately after the confirmation
- **WHEN** the confirmation "Logged ₹250 to Food" appears and the app is force-stopped at once
- **THEN** on reopening, the ₹250 entry is present

### Requirement: A failed save records nothing
When an entry cannot be saved, the app SHALL NOT record it, SHALL leave every figure unchanged, SHALL tell the user it could not be saved, and SHALL keep the log flow open with the amount as entered.

#### Scenario: Save fails
- **WHEN** the user taps Food with ₹250 entered and the save fails
- **THEN** no confirmation appears, the remaining amount is unchanged, a message says the entry could not be saved, and the log flow still shows ₹250

### Requirement: Undo removes the saved entry
Undoing an entry SHALL remove it from the saved data as well as from the screen.

#### Scenario: Undo, then restart
- **WHEN** the user logs ₹250 to Food, taps Undo, and the app is force-stopped and opened again
- **THEN** the ₹250 entry is not present

### Requirement: Saving is fast
Saving one entry SHALL take 100 milliseconds or less, measured from the filing tap to the entry being saved, as the median of 20 consecutive saves with 2,000 entries already stored.

#### Scenario: Twenty saves on a full ledger
- **WHEN** 20 expenses are logged one after another on a device already holding 2,000 entries
- **THEN** the median save time is 100 milliseconds or less

### Requirement: Start-up is fast
From a cold start, the home screen SHALL be showing the user's figures and accepting input within 1.5 seconds, with 2,000 entries already stored.

#### Scenario: Cold start with a full ledger
- **WHEN** the app is launched from a stopped state on a device holding 2,000 entries
- **THEN** the home screen is interactive with correct figures within 1.5 seconds

### Requirement: Returning users never see setup
While saved data is being read at start-up, the app SHALL show only its background, and SHALL NOT show the setup screen to a user who has completed setup.

#### Scenario: Launch after setup
- **WHEN** a user who has completed setup launches the app
- **THEN** the home screen appears and the setup screen is never shown, even briefly

### Requirement: Data is encrypted at rest
Saved data SHALL be encrypted on the device with AES-256. The encryption key SHALL be held only in the platform's secure key storage and SHALL NOT be written to any ordinary file.

#### Scenario: Reading the file without the key
- **WHEN** the saved data file is copied off the device and opened with a standard database tool
- **THEN** it cannot be read, and no amount, note or category name appears in it as plain text

#### Scenario: Looking for the key
- **WHEN** the app's ordinary files are inspected
- **THEN** the encryption key is not among them

### Requirement: Unreadable data is never treated as no data
When saved data exists but cannot be opened, the app SHALL say so, SHALL offer to try again, and SHALL NOT show the setup screen, show an empty ledger, or delete or overwrite the saved data.

#### Scenario: Data cannot be opened
- **WHEN** the app starts and its saved data cannot be opened
- **THEN** a message explains that Tide's data could not be opened and offers Retry, and the saved file is left as it is

#### Scenario: Retry succeeds
- **WHEN** the user taps Retry and the data opens
- **THEN** the home screen appears with the user's figures

### Requirement: Saved data stays on the device
Saved data SHALL be excluded from the operating system's automatic cloud backup and device-to-device transfer, because the key that opens it does not leave the device.

#### Scenario: Automatic backup runs
- **WHEN** the operating system backs up the app's data
- **THEN** Tide's saved data file is not included

### Requirement: Entries keep their exact moment
Each entry SHALL be saved with the exact moment it was recorded, and SHALL count toward the calendar month it falls in by the device's local time.

#### Scenario: Just after midnight in India
- **WHEN** an expense is logged at 00:10 on 1 November, Indian time, which is still 31 October in universal time
- **THEN** it counts toward November

#### Scenario: Late on the last day
- **WHEN** an expense is logged at 23:50 on 31 October, local time
- **THEN** it counts toward October
