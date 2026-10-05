# Spec Delta

## Purpose

Covers recording an expense or income entry by hand: how the log flow opens, how an amount is set, how the entry is filed, how it can be undone, and how long it took. Its target is a median of 3 seconds or less per expense.

## ADDED Requirements

### Requirement: Opening the log flow
The system SHALL open the log flow when the user pulls down on the home screen past a short threshold, and when the user taps the visible handle at the top of the home screen. The log flow SHALL open ready to record an expense.

#### Scenario: Pull down on the vessel
- **WHEN** the user drags downward on the home screen past the threshold and releases
- **THEN** the log flow opens in expense mode

#### Scenario: Short drag
- **WHEN** the user drags downward less than the threshold and releases
- **THEN** the home screen stays as it was

#### Scenario: Handle tapped
- **WHEN** the user taps the handle
- **THEN** the log flow opens in expense mode

### Requirement: Cancelling the log flow
The system SHALL let the user leave the log flow without recording anything.

#### Scenario: Cancel
- **WHEN** the user taps Cancel with an amount set
- **THEN** the home screen returns, no entry is recorded and the budget status is unchanged

### Requirement: Amount range
An entry amount SHALL be a whole number of rupees from ₹1 to ₹9,99,999. The log flow SHALL show the current amount at all times.

#### Scenario: Upper bound
- **WHEN** the user tries to raise the amount above ₹9,99,999
- **THEN** the amount stays at ₹9,99,999

#### Scenario: Lower bound
- **WHEN** the user tries to lower the amount below ₹0
- **THEN** the amount stays at ₹0

### Requirement: Number pad entry
The log flow SHALL offer an on-screen number pad with the digits 0 to 9 and a delete key, through which any amount in the allowed range can be entered. The first digit pressed SHALL replace whatever amount was set before.

#### Scenario: Typing an odd amount
- **WHEN** the user presses 3 then 7
- **THEN** the amount is ₹37

#### Scenario: Correcting a digit
- **WHEN** the amount is ₹1,850 and the user presses delete
- **THEN** the amount is ₹185

### Requirement: Amount ring entry
The log flow SHALL offer an amount ring that raises the amount when turned clockwise and lowers it when turned anticlockwise, in steps that grow as the ring is turned faster, with a haptic tick for each step.

#### Scenario: Slow turn
- **WHEN** the user turns the ring slowly clockwise
- **THEN** the amount rises in small steps with a tick per step

#### Scenario: Fast turn
- **WHEN** the user spins the ring quickly clockwise
- **THEN** the amount rises in larger steps than during a slow turn

#### Scenario: Turning back
- **WHEN** the user turns the ring anticlockwise
- **THEN** the amount falls

### Requirement: Frequent-amount chips
The log flow SHALL offer up to five chips showing the expense amounts the user has recorded most often, most frequent first, with ties broken by the more recently used amount. Tapping a chip SHALL set the amount to that chip's value.

#### Scenario: Tapping a chip
- **WHEN** the user taps the "₹250" chip
- **THEN** the amount is ₹250

#### Scenario: A new habit appears
- **WHEN** the user records ₹20 more often than any other amount
- **THEN** ₹20 is the first chip the next time the log flow opens

### Requirement: Filing an expense
In expense mode the log flow SHALL show every category as an equal-sized pebble in a fixed position. Tapping a pebble with an amount of at least ₹1 SHALL record an expense with that amount, that category, the current date and time and the note, return to the home screen, and show a confirmation naming the amount and the category. No separate save action SHALL be needed.

#### Scenario: One tap files the entry
- **WHEN** the amount is ₹250 and the user taps the Food pebble
- **THEN** an expense of ₹250 in Food is recorded, the home screen returns with ₹250 less remaining, and the confirmation reads "Logged ₹250 to Food"

#### Scenario: Pebble positions do not move
- **WHEN** the user opens the log flow on two different days with different spending
- **THEN** each category's pebble is in the same place and the same size both times

### Requirement: Amount must be set
The system SHALL NOT record an entry with an amount of ₹0, and SHALL tell the user to set an amount.

#### Scenario: Filing with no amount
- **WHEN** the amount is ₹0 and the user taps a pebble
- **THEN** no entry is recorded, the log flow stays open and a message says to set an amount first

### Requirement: Optional note
The log flow SHALL accept an optional note. When no note is given, the entry's note SHALL be the category name for an expense and the source name for income.

#### Scenario: Note given
- **WHEN** the user types "Lunch with the team" and files ₹340 to Food
- **THEN** the entry's note is "Lunch with the team"

#### Scenario: Note left empty
- **WHEN** the user files ₹340 to Food without typing a note
- **THEN** the entry's note is "Food"

### Requirement: Recording income
The log flow SHALL offer an income mode. In income mode it SHALL show a set of income sources in place of the category pebbles, and tapping a source with an amount of at least ₹1 SHALL record an income entry, return to the home screen and show a confirmation naming the amount and the source.

#### Scenario: Adding freelance income
- **WHEN** the user switches to income mode, sets ₹5,000 and taps Freelance
- **THEN** an income entry of ₹5,000 is recorded, the amount available and the amount remaining each rise by ₹5,000, and the confirmation reads "Added ₹5,000 from Freelance"

### Requirement: Undo
The confirmation shown after an entry is recorded SHALL offer an Undo button for 10 seconds. Using it SHALL remove that entry and restore the budget status to what it was before. After 10 seconds the confirmation and its Undo button SHALL disappear.

#### Scenario: Undo within the window
- **WHEN** the user files ₹250 to Food and taps Undo 4 seconds later
- **THEN** the entry is removed and the amount remaining is ₹250 higher again

#### Scenario: Window has passed
- **WHEN** 10 seconds pass after an entry is recorded
- **THEN** the Undo button is no longer offered and the entry stays

#### Scenario: A second entry replaces the first confirmation
- **WHEN** the user records a second entry while the first confirmation is still showing
- **THEN** Undo applies to the second entry only

### Requirement: Feedback on filing
The system SHALL give a haptic pulse when an entry is recorded and a different haptic pulse when filing is refused.

#### Scenario: Entry recorded
- **WHEN** an expense is filed
- **THEN** the phone gives a success pulse as the home screen returns

### Requirement: Time-to-log measurement
The system SHALL measure, for every recorded expense, the time from the log flow opening to the expense being filed, together with the amount-entry method used last. It SHALL show that time in the confirmation, and SHALL make available from the home screen a summary of the number of entries and the median time for each method and overall, with a way to clear it. Undone entries SHALL be left out of the summary.

#### Scenario: Time shown after filing
- **WHEN** the user opens the log flow and files an expense 2.4 seconds later
- **THEN** the confirmation includes "2.4 s"

#### Scenario: Median per method
- **WHEN** the user has logged three expenses with the pad in 2.1, 2.6 and 3.4 seconds and one with the ring in 4.0 seconds
- **THEN** the summary shows pad: 3 entries, median 2.6 s; ring: 1 entry, median 4.0 s; overall: 4 entries, median 3.0 s

#### Scenario: Undone entry
- **WHEN** an expense is undone
- **THEN** its time no longer counts in the summary

#### Scenario: Clearing the summary
- **WHEN** the user clears the summary
- **THEN** all counts are zero and recorded entries are unaffected
