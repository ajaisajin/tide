# Spec Delta

## Purpose

The Vessel is Tide's home screen. It presents the month's budget status as a vessel of liquid so that a person can tell how much is left at a glance, and it is the surface every other action starts from.

## ADDED Requirements

### Requirement: Budget figures always visible
The home screen SHALL always show the amount remaining as its largest text, together with the current month, the mood label of the status band, the amount available, the percentage full, and the safe-to-spend figure for today. None of these SHALL require a tap, a long press or any other action to reveal.

#### Scenario: Opening the app mid-month
- **WHEN** the app opens with ₹13,601 remaining of ₹30,000 on 5 October
- **THEN** the screen shows "₹13,601", "October", "Running lower", "left of ₹30,000", "45% full" and "Safe today: ₹503"

### Requirement: Liquid level shows the fill level
The home screen SHALL show a liquid whose height rises and falls with the fill level. The liquid SHALL always remain visible at the lowest fill level, and SHALL never cover the remaining-amount text at the highest.

#### Scenario: Full budget
- **WHEN** the fill level is 1
- **THEN** the liquid is at its highest and the remaining amount is still fully readable above it

#### Scenario: Nearly empty
- **WHEN** the fill level is 0.02
- **THEN** a thin band of liquid is still visible at the bottom of the screen

### Requirement: Colour follows the status band
The liquid SHALL be teal in the "Calm water" band, amber in "Running lower" and coral in "Nearly dry". The status band SHALL also be stated in text, so that status never depends on colour alone.

#### Scenario: Crossing into a lower band
- **WHEN** an expense takes the fill level from 0.52 to 0.48
- **THEN** the liquid changes from teal to amber and the mood label changes from "Calm water" to "Running lower"

### Requirement: Overspent state
When the status band is "Below the line", the home screen SHALL replace the liquid with a visibly different overspent band, show the amount overspent as a negative figure, and show safe to spend today as ₹0. The overspent band SHALL grow as the overspend grows.

#### Scenario: Overspent by ₹2,000
- **WHEN** the amount remaining is −₹2,000
- **THEN** the screen shows "−₹2,000", "Below the line", "Safe today: ₹0" and the overspent band instead of liquid

#### Scenario: Returning above the line
- **WHEN** an income entry brings the amount remaining back to ₹500
- **THEN** the liquid returns and the overspent band is gone

### Requirement: Category pebbles
The home screen SHALL show one pebble per category with the category name and its spend for the month. A pebble SHALL grow as the category uses more of its limit, SHALL never be smaller than a comfortable touch target, and SHALL sit visibly lower and take a warning colour when the category is over its limit.

#### Scenario: Category with little spend
- **WHEN** Fun has used 33% of its limit
- **THEN** its pebble is smaller than the pebble of a category that has used 90% of its limit

#### Scenario: Category over its limit
- **WHEN** Shopping is over its limit
- **THEN** its pebble sits lower than the others and is outlined in the warning colour

### Requirement: Level change is animated
When an entry is recorded or removed, the home screen SHALL animate the liquid from its old level to its new level with a visible disturbance of the surface that settles within about one second.

#### Scenario: Expense recorded
- **WHEN** an expense is filed and the home screen returns
- **THEN** the liquid visibly drains to the new level, the surface sloshes, and it settles

#### Scenario: Income recorded
- **WHEN** an income entry is recorded
- **THEN** the liquid visibly rises to the new level

### Requirement: Liquid responds to tilt
While the home screen is showing, the liquid surface SHALL lean in response to the phone being tilted side to side and SHALL settle level when the phone is held still. The system SHALL NOT read motion sensors while the home screen is not showing.

#### Scenario: Tilting the phone
- **WHEN** the phone is rolled to the left
- **THEN** the liquid surface leans to follow gravity, then settles once the phone stops moving

#### Scenario: Log flow is open
- **WHEN** the log flow covers the home screen
- **THEN** motion sensors are not being read

### Requirement: Still water mode
The home screen SHALL show the liquid as a flat, unmoving level, with no waves, tilt response or slosh, when the device's reduce-motion setting is on, or when rendering has been slower than 50 frames per second for two seconds. Level and colour SHALL still reflect the fill level and status band.

#### Scenario: Reduce motion is on
- **WHEN** the device's reduce-motion setting is on and an expense is recorded
- **THEN** the liquid shows the new level without waves or slosh

#### Scenario: Sustained slow frames
- **WHEN** rendering stays below 50 frames per second for two seconds
- **THEN** the liquid switches to still water and stays there until the app is next opened

### Requirement: Screen reader summary
The home screen SHALL expose the budget status to screen readers as a single spoken summary containing the percentage left, the amount remaining and the safe-to-spend figure, and SHALL give every pebble a label containing the category name, its spend and its limit.

#### Scenario: Reading the home screen
- **WHEN** a screen reader focuses the vessel with ₹13,601 remaining of ₹30,000
- **THEN** it speaks a summary that includes "45% left", "₹13,601" and "safe today ₹503"

#### Scenario: Reading a pebble over its limit
- **WHEN** a screen reader focuses the Shopping pebble and Shopping is over its limit
- **THEN** it speaks the category name, its spend, its limit and "over limit"
