# Spec Delta

## Purpose

Defines how Tide turns a monthly budget and a list of entries into the figures every screen shows: how much is available, how much is left, how full the vessel is, how the month is going, and where each category stands against its limit.

## ADDED Requirements

### Requirement: Monthly position
The system SHALL compute the amount available for the current calendar month as the monthly budget plus all income entries dated in that month, and the amount remaining as the amount available minus all expense entries dated in that month. Entries dated in other months SHALL NOT affect these figures.

#### Scenario: Expenses only
- **WHEN** the budget is ₹30,000 and the month's expenses total ₹16,399
- **THEN** the amount available is ₹30,000 and the amount remaining is ₹13,601

#### Scenario: Income raises the amount available
- **WHEN** the budget is ₹30,000, expenses total ₹16,399 and an income entry of ₹5,000 is dated in the month
- **THEN** the amount available is ₹35,000 and the amount remaining is ₹18,601

#### Scenario: Entry from another month
- **WHEN** an expense is dated in the previous month
- **THEN** it does not change the current month's amount remaining

### Requirement: Fill level
The system SHALL express the month's position as a fill level between 0 and 1, equal to the amount remaining divided by the amount available. The fill level SHALL be 0 when the amount remaining is zero or negative, or when the amount available is zero.

#### Scenario: Part of the budget is left
- **WHEN** ₹13,601 remains of ₹30,000 available
- **THEN** the fill level is 0.45 to two decimal places

#### Scenario: Overspent month
- **WHEN** the amount remaining is −₹2,000
- **THEN** the fill level is 0

### Requirement: Status band
The system SHALL classify the month into exactly one status band, each with a mood label: "Calm water" when the fill level is above 0.5, "Running lower" when it is above 0.25 and at most 0.5, "Nearly dry" when it is at most 0.25 and the amount remaining is not negative, and "Below the line" when the amount remaining is negative.

#### Scenario: Above half
- **WHEN** the fill level is 0.62
- **THEN** the status band is "Calm water"

#### Scenario: Exactly half
- **WHEN** the fill level is exactly 0.5
- **THEN** the status band is "Running lower"

#### Scenario: Exactly nothing left
- **WHEN** the amount remaining is exactly ₹0
- **THEN** the status band is "Nearly dry"

#### Scenario: Overspent
- **WHEN** the amount remaining is −₹2,000
- **THEN** the status band is "Below the line"

### Requirement: Safe to spend today
The system SHALL compute a safe-to-spend figure for today as the amount remaining divided by the number of days left in the month, counting today, rounded down to a whole rupee. The figure SHALL be ₹0 when the amount remaining is zero or negative.

#### Scenario: Mid-month
- **WHEN** ₹13,601 remains on 5 October
- **THEN** safe to spend today is ₹503, from 27 days left

#### Scenario: Last day of the month
- **WHEN** ₹800 remains on the last day of the month
- **THEN** safe to spend today is ₹800

#### Scenario: Overspent
- **WHEN** the amount remaining is negative
- **THEN** safe to spend today is ₹0

### Requirement: Category position
The system SHALL compute, for each category, the total of the month's expenses filed to it and the share of its monthly limit that total represents. A category SHALL be "near its limit" when the share is at least 80% and below 100%, and "over its limit" when the share is 100% or more.

#### Scenario: Within the limit
- **WHEN** Food has a limit of ₹6,000 and expenses of ₹2,330
- **THEN** Food's spend is ₹2,330, its share is 39%, and it is neither near nor over its limit

#### Scenario: Near the limit
- **WHEN** Shopping has a limit of ₹2,000 and expenses of ₹1,850
- **THEN** Shopping is near its limit

#### Scenario: Limit reached
- **WHEN** Shopping has a limit of ₹2,000 and expenses of ₹2,000
- **THEN** Shopping is over its limit

#### Scenario: Income is not category spend
- **WHEN** an income entry is recorded
- **THEN** no category's spend changes

### Requirement: Exact amounts in Indian format
The system SHALL hold every amount exactly, with no rounding drift when amounts are added or subtracted, and SHALL display amounts with the rupee sign and Indian digit grouping.

#### Scenario: Lakh grouping
- **WHEN** an amount of one lakh fifty thousand rupees is displayed
- **THEN** it reads "₹1,50,000"

#### Scenario: Repeated small entries
- **WHEN** ten expenses of ₹37 are recorded against a budget of ₹30,000
- **THEN** the amount remaining is exactly ₹29,630
