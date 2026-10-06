# monthly-budget Specification

## Purpose

Covers how a person tells Tide what they have to spend: their monthly income, the budget for each month and the limit for each category, from first-run setup through later changes and the move from one month to the next.

## Requirements

### Requirement: First-run setup
On a device with no budget saved, the app SHALL open on a setup screen and SHALL NOT show the home screen or the log flow until setup is completed.

#### Scenario: New install
- **WHEN** the app is opened for the first time
- **THEN** the setup screen is shown, not the home screen

#### Scenario: Setup abandoned
- **WHEN** the user closes the app during setup and opens it again
- **THEN** the setup screen is shown again from the start

### Requirement: Monthly income
The setup screen SHALL ask for the user's monthly income as a whole number of rupees from ₹1 to ₹99,99,999. Income SHALL be a reference figure only: it SHALL NOT be recorded as an income entry and SHALL NOT add to the amount available.

#### Scenario: Income entered
- **WHEN** the user enters ₹45,000 as monthly income
- **THEN** the screen shows ₹45,000 as income and offers the vessel to set the budget

#### Scenario: Income is not money in the vessel
- **WHEN** setup is completed with income ₹45,000 and budget ₹30,000
- **THEN** the amount available on the home screen is ₹30,000

### Requirement: Setting the budget by filling the vessel
On the same screen, the user SHALL set the budget by dragging the vessel's water level up or down. The budget SHALL equal the share of income the level represents, in steps of ₹500 (₹100 when income is below ₹10,000), from ₹0 up to the income. The screen SHALL show the budget and the amount set aside (income minus budget) while dragging, with a haptic tick for each step.

#### Scenario: Dragging up
- **WHEN** income is ₹45,000 and the user drags the level up to two thirds of the vessel
- **THEN** the budget reads ₹30,000 and the amount set aside reads ₹15,000

#### Scenario: Top of the vessel
- **WHEN** the user drags the level past the top
- **THEN** the budget stays at the income, ₹45,000, and the amount set aside reads ₹0

#### Scenario: Small income
- **WHEN** income is ₹6,000 and the user drags the level
- **THEN** the budget changes in steps of ₹100

### Requirement: Typing the budget
The user SHALL be able to type the budget instead of dragging, as any whole number of rupees from ₹1 up to the income. The water level SHALL move to match a typed budget.

#### Scenario: Exact amount
- **WHEN** income is ₹45,000 and the user types ₹28,750
- **THEN** the budget reads ₹28,750 and the water level shows that share of the vessel

#### Scenario: More than income
- **WHEN** income is ₹45,000 and the user types ₹50,000
- **THEN** the budget is not accepted and a message says it cannot be more than the income

### Requirement: Completing setup
Setup SHALL be completed only by confirming an income and a budget of at least ₹1. On confirmation the app SHALL save the income, save the budget as the current month's budget, give each category its default limit, and show the home screen with the whole budget remaining.

#### Scenario: Confirming
- **WHEN** the user confirms income ₹45,000 and budget ₹30,000
- **THEN** the home screen shows ₹30,000 remaining, "left of ₹30,000", "100% full", and every category at ₹0

#### Scenario: No budget yet
- **WHEN** the budget is ₹0
- **THEN** setup cannot be confirmed

### Requirement: Default category limits
When a budget is first set, each default category SHALL receive a limit equal to its share of the budget, rounded down to a multiple of ₹100 and never less than ₹100. The shares SHALL be Food 20%, Bills 35%, Travel 10%, Shopping 7%, Fun 5% and Health 5%.

#### Scenario: Budget of ₹30,000
- **WHEN** setup is completed with a budget of ₹30,000
- **THEN** the limits are Food ₹6,000, Bills ₹10,500, Travel ₹3,000, Shopping ₹2,100, Fun ₹1,500 and Health ₹1,500

#### Scenario: Rounding down
- **WHEN** setup is completed with a budget of ₹18,400
- **THEN** Food's limit is ₹3,600 and Shopping's limit is ₹1,200

#### Scenario: Very small budget
- **WHEN** setup is completed with a budget of ₹1,000
- **THEN** no category's limit is below ₹100

### Requirement: Opening the budget screen from home
The home screen SHALL let the user open a budget screen showing the current income, the current month's budget and every category's limit. Leaving that screen without saving SHALL change nothing.

#### Scenario: Opening
- **WHEN** the user taps the budget line on the home screen
- **THEN** the budget screen opens showing the saved income, budget and six category limits

#### Scenario: Leaving without saving
- **WHEN** the user changes the budget on that screen and leaves without saving
- **THEN** the home screen's figures are unchanged

### Requirement: Changing the budget and income
From the budget screen the user SHALL be able to change the income and the current month's budget, by the same dragging and typing as in setup. Saving SHALL update the home screen's figures at once. Changing the budget SHALL NOT change any category's limit or any earlier month's budget.

#### Scenario: Raising the budget mid-month
- **WHEN** ₹13,601 remains of ₹30,000 and the user saves a budget of ₹32,000
- **THEN** the home screen shows ₹15,601 remaining and "left of ₹32,000"

#### Scenario: Lowering the budget below what is spent
- **WHEN** ₹16,399 is spent and the user saves a budget of ₹15,000
- **THEN** the home screen shows the overspent state at −₹1,399

#### Scenario: Category limits untouched
- **WHEN** the user changes the budget from ₹30,000 to ₹32,000
- **THEN** Food's limit is still ₹6,000

### Requirement: Changing a category's limit
From the budget screen the user SHALL be able to set each category's limit to any whole number of rupees from ₹1 to ₹99,99,999. The screen SHALL show the total of all limits and SHALL say when that total is more than the budget, without preventing it.

#### Scenario: Raising a limit
- **WHEN** Food has ₹2,330 spent of ₹6,000 and the user saves a Food limit of ₹8,000
- **THEN** Food's pebble reflects ₹2,330 of ₹8,000

#### Scenario: Limits add up to more than the budget
- **WHEN** the limits total ₹34,000 and the budget is ₹30,000
- **THEN** the screen says the limits are ₹4,000 more than the budget, and saving is still allowed

### Requirement: One budget per month, carried forward
Each calendar month SHALL have its own budget. A month in which no budget has been set SHALL use the budget of the most recent earlier month that has one.

#### Scenario: New month with nothing set
- **WHEN** October's budget is ₹30,000 and the app is opened in November
- **THEN** November's budget is ₹30,000

#### Scenario: Changing the new month only
- **WHEN** the user then sets November's budget to ₹32,000
- **THEN** October's budget is still ₹30,000

### Requirement: Figures follow the calendar
When the date moves into a new month while the app is open, or the app returns to the foreground in a new month, the home screen SHALL show the new month's figures without the app being restarted.

#### Scenario: Midnight at month end
- **WHEN** the app is on the home screen as 31 October becomes 1 November, with a budget of ₹30,000
- **THEN** the screen shows "November", ₹30,000 remaining and every category at ₹0

#### Scenario: Returning after a few days
- **WHEN** the app was last used on 30 October and is brought back to the foreground on 2 November
- **THEN** the screen shows November's figures

### Requirement: Budget controls are accessible
The vessel used to set the budget SHALL be operable without dragging and SHALL be exposed to screen readers as an adjustable value that announces the budget amount.

#### Scenario: Screen reader adjusts the budget
- **WHEN** a screen reader user focuses the vessel on the setup screen and uses the increase action
- **THEN** the budget rises by one step and the new amount is announced
