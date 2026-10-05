# Expense Tracker App — Business Requirements Document

Oct 5, 2026 · @Ajai

## Executive summary

We will build **Tide** (working name), an expense tracker for iOS and Android where money behaves like water: the month's budget is a liquid level that drains as you spend and responds to touch, tilt and time. The goal is to make logging an expense take under 3 seconds and make budget status readable at a glance, without a single list-of-cards screen or pie chart.

| Item | Detail |
| --- | --- |
| Document | Business Requirements Document (BRD) |
| Version | 0.1 draft |
| Product | Tide — personal expense tracker (mobile) |
| Platforms | iOS 16+, Android 10+ |
| Primary market | India (INR first), multi-currency ready |
| Status | Draft for review |

What makes it different: no tab bar, no transaction feed as home, no donut charts. Instead a single living "vessel" screen, a radial command dial, gesture-first entry and a scrubbable time river.

## Business objectives and success metrics

Most people abandon expense apps within weeks because logging is a chore and the screens all look like bank statements. Tide wins on two things: speed of entry and an emotional, glanceable sense of "how much is left".

**Problem statement**

- Manual entry takes 15–30 seconds in typical apps (open, tap +, pick category from a long list, type, save).
- Dashboards show charts that need reading, not feeling; users don't change behaviour.
- Design across the category is interchangeable: card lists, donut charts, bottom tab bars.

**Objectives and KPIs (first 12 months after launch)**

| Objective | KPI | Target |
| --- | --- | --- |
| Effortless logging | Median time to log one expense | ≤ 3 seconds |
| Habit formation | Day-30 retention | ≥ 35% |
| Engagement | Days per week with ≥ 1 entry, active users | ≥ 4 |
| Behaviour change | Users finishing a month within budget | ≥ 55% |
| Distinctiveness | Store rating mentioning design or "fun" | ≥ 20% of reviews |
| Revenue | Free-to-premium conversion | ≥ 4% |
| Growth | Installs | 100,000 |

## Scope and target users

Version 1 is a personal, single-user tracker with optional shared "pools" for couples and flatmates; business accounting is out.

**In scope (v1)**

- Expense and income logging (manual, voice, SMS/UPI auto-capture on Android, receipt scan)
- Monthly budget with category "streams"
- Recurring bills and subscriptions
- Insights, goals (savings), reminders
- Shared pools (split expenses with up to 6 people)
- Offline-first with cloud sync and backup; export to CSV/PDF

**Out of scope (v1)**

- Direct bank account linking (Account Aggregator) — planned for v2
- Investments, tax filing, credit score
- Business/GST invoicing, multi-user business ledgers
- Web and tablet apps

**Personas**

| Persona | Profile | Need | What Tide must do |
| --- | --- | --- | --- |
| Riya, 24 | First job, Bengaluru, pays mostly by UPI | Knows money vanishes but not where | Auto-capture UPI spends, show what's left in one glance |
| Arjun, 32 | Married, shared household costs | Fair split with partner without arguments | Shared pools, settle-up in one tap |
| Meera, 45 | Runs home budget for a family of four | Control of monthly bills and kids' spends | Recurring bills, category limits, reminders |
| Kabir, 20 | Student, small allowance | Make money last the month | Daily safe-to-spend number, playful feedback |

## Design concept and interaction model

Tide's design rule: the user should *feel* their budget before they read a number. Every screen is built on one metaphor — money as water — and every action is a gesture, not a form.

**Design principles**

1. **One living screen, not many tabs.** The home is a single full-screen vessel; everything else opens over it as layers.
2. **Gesture first, buttons second.** Every core action has a gesture; buttons exist only as accessible fallbacks.
3. **Motion carries meaning.** Animation shows cause and effect (a spend drains the vessel), never decoration.
4. **Numbers on demand.** Default view is visual; long-press anywhere reveals exact figures.
5. **No category-standard patterns.** Banned in v1: bottom tab bar, transaction card feed as home, donut/pie charts, floating "+" button.

**Signature screens and interactions**

| Element | What the user sees | Interaction |
| --- | --- | --- |
| The Vessel (home) | A full-screen glass of liquid; level = budget left this month. Colour shifts calm teal → amber → coral as it drains | Tilt the phone and the liquid sloshes (gyroscope). Tap the surface to see "safe to spend today". Long-press for exact numbers |
| Category Pebbles | Each category is a pebble resting in the liquid, sized by spend | Drag a pebble out to open that category; pebbles sink when over limit |
| Drop to log | — | Swipe down from the top edge: a droplet forms. Spin the amount ring with your thumb, flick the drop onto a pebble to file it. Target ≤ 3 seconds |
| Command Dial | A radial menu that blooms from the thumb position | Press-and-hold anywhere on the vessel; slide to Log, Scan, Speak, Goals, Pools, Settings |
| Time River | Days flow as a horizontal river; width of each day = spend | Pinch to zoom day ↔ week ↔ month ↔ year; scrub to rewind the vessel level to any date |
| Ripple Insights | Insights appear as ripples on the surface, one at a time | Tap a ripple to expand; swipe away to dismiss |
| Goal Wells | Savings goals as wells that fill as you save | Drag surplus from the vessel into a well at month end |
| Shake to undo | — | Shake to undo the last entry, with haptic confirmation |

**Visual identity**

- Palette: deep ink background (dark-first), liquid gradients that encode state; light theme available.
- Typography: one expressive display face for the big number, a neutral sans for everything else.
- Haptics: a soft tick per ₹100 while spinning the amount ring; a heavier pulse when a category crosses 80% of its limit.
- Sound (optional, off by default): water drop on save.

**Accessibility**

Every gesture has a visible button alternative, full screen-reader labels ("Budget 62% left, ₹18,400"), reduced-motion mode that freezes the liquid into a clean level bar, and colour states backed by text and icons.

**Navigation map**

&#91;embedded content: navigation map · 1 home screen, 4 gestures, 6 dial actions\]

There is no tab bar: the Vessel is always underneath, and every other view is one gesture away and dismisses back to it with a swipe.

## Functional requirements

Priority uses MoSCoW: M = must for launch, S = should, C = could (post-launch).

| ID | Area | Requirement | Priority |
| --- | --- | --- | --- |
| FR-01 | Onboarding | Sign up with phone OTP, Google or Apple; guest mode with local-only data | M |
| FR-02 | Onboarding | Set monthly income and budget in one screen by "filling the vessel" (drag up to amount) | M |
| FR-03 | Logging | Log expense via Drop gesture: amount ring, category flick, optional note; ≤ 3 s median | M |
| FR-04 | Logging | Log income (drag upward fills vessel) | M |
| FR-05 | Logging | Voice entry: "Spent 250 on lunch" parsed to amount, category, note (English, Hindi) | S |
| FR-06 | Logging | Receipt scan: camera OCR extracts amount, merchant, date for confirmation | S |
| FR-07 | Auto-capture | Android: read bank/UPI SMS with user consent, suggest entries for one-tap confirm | M |
| FR-08 | Auto-capture | iOS: share-sheet and Shortcuts integration to send payment info to Tide | S |
| FR-09 | Categories | 10 default categories as pebbles; create, rename, recolour, merge | M |
| FR-10 | Categories | Smart suggestion learns merchant → category after 2 confirmations | S |
| FR-11 | Budget | Monthly budget, per-category limits, daily "safe to spend" figure | M |
| FR-12 | Budget | Rollover of unspent amount to next month or to a Goal Well (user choice) | S |
| FR-13 | Recurring | Recurring bills/subscriptions with due-date reminders; auto-log on due date | M |
| FR-14 | Time River | Browse history by day/week/month/year with pinch zoom; search by text, amount, category | M |
| FR-15 | Edit | Edit or delete any entry; shake-to-undo last action within 10 s | M |
| FR-16 | Insights | Weekly ripple insights (e.g. "Food up 30% vs last week"), max 1 per day | S |
| FR-17 | Goals | Create savings goals with target and date; move surplus into wells | S |
| FR-18 | Pools | Shared pools with up to 6 members; equal/custom splits; settle-up via UPI link | S |
| FR-19 | Notifications | Budget threshold alerts at 50/80/100%, bill reminders, daily log nudge (configurable) | M |
| FR-20 | Multi-currency | Log in foreign currency with conversion to home currency | C |
| FR-21 | Export | Export to CSV and PDF monthly statement | M |
| FR-22 | Security | App lock with biometrics/PIN; hide-amounts mode | M |
| FR-23 | Widgets | Home-screen widget showing the vessel level and one-tap log | S |
| FR-24 | Personalisation | Vessel skins (glass, clay jar, ocean, lantern) — premium | C |

## Non-functional requirements

The liquid animation is the product, so performance targets are as strict as security ones.

| ID | Category | Requirement |
| --- | --- | --- |
| NFR-01 | Performance | Vessel animation at 60 fps on mid-range Android (e.g. 4 GB RAM devices); 120 fps on ProMotion iOS |
| NFR-02 | Performance | Cold start to interactive vessel ≤ 1.5 s; entry save ≤ 100 ms (local) |
| NFR-03 | Offline | All core features work offline; sync resolves conflicts last-write-wins per field |
| NFR-04 | Security | AES-256 encryption at rest, TLS 1.3 in transit; biometric lock |
| NFR-05 | Privacy | SMS read on-device only; raw SMS never uploaded; explicit consent screen |
| NFR-06 | Compliance | India DPDP Act 2023; Google Play SMS permission policy; Apple App Store privacy labels |
| NFR-07 | Accessibility | WCAG 2.2 AA; screen reader support; reduced-motion mode; text scaling to 200% |
| NFR-08 | Battery | Gyroscope used only while vessel is on screen; < 2% battery per day of normal use |
| NFR-09 | Reliability | Crash-free sessions ≥ 99.5%; daily encrypted cloud backup |
| NFR-10 | Scalability | Backend supports 500,000 users without re-architecture |
| NFR-11 | Localisation | English and Hindi at launch; INR formatting (lakh/crore) supported |
| NFR-12 | App size | Install size ≤ 40 MB |

## Data, integrations and monetisation

Tide is freemium: everything needed to track money is free; premium sells convenience and delight.

**Core data entities**

| Entity | Key fields |
| --- | --- |
| User | id, name, phone/email, home currency, locale, monthly income |
| Transaction | id, type (expense/income), amount, currency, category, merchant, note, date-time, source (manual/voice/SMS/scan), pool id |
| Category | id, name, colour, icon, monthly limit |
| Budget | month, total, per-category limits, rollover rule |
| Recurring | id, amount, category, frequency, next due date |
| Goal | id, name, target amount, target date, saved amount |
| Pool | id, members, split rule, balances |

**Integrations**

- Android SMS (on-device parsing) for bank and UPI alerts
- UPI intent links for settle-up in pools
- Device OCR (Google ML Kit / Apple Vision) for receipts
- Speech-to-text (on-device where available) for voice entry
- Firebase or equivalent for auth, push notifications, crash reporting
- Currency rates API (for FR-20)

**Monetisation**

| Plan | Price (indicative) | Includes |
| --- | --- | --- |
| Free | ₹0 | Unlimited manual + SMS entries, 1 budget, 10 categories, 1 pool, basic insights |
| Tide Plus | ₹79/month or ₹599/year | Receipt scan, voice entry, unlimited pools and goals, vessel skins, advanced insights, PDF export |

No ads in v1: ads would break the calm, single-screen design.

## Assumptions, risks and roadmap

The biggest risk is that a novel interface confuses users; the plan front-loads usability testing before any backend scale work.

**Assumptions**

- Launch market is India, home currency INR, users pay mainly via UPI.
- Cross-platform build (Flutter or React Native) with a custom rendering layer for the liquid (e.g. Rive or Skia shaders).
- One product team: 1 PM, 1 product designer, 1 motion designer, 3 mobile engineers, 1 backend engineer, 1 QA.

**Risks**

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Gesture-first UI is not discoverable | High | Interactive 60-second onboarding; visible button fallbacks; usability tests with 15+ users per round |
| Google Play restricts SMS permission | High | Apply under the financial-tracking exception; fallback to notification-listener and manual entry |
| Animation lags on low-end phones | Medium | Performance budget per frame; auto-switch to "still water" mode under 50 fps |
| Design copied by competitors | Medium | Ship fast, file design registration for the vessel concept, keep iterating skins |
| Low premium conversion | Medium | Test pricing in 2 cohorts; annual plan discount |

**Roadmap**

&#91;embedded content: roadmap · 5 phases, 3 gates\]

No build starts until prototype testing shows users can log an expense in 3 seconds or less without help.

**Sign-off**

| Role | Name | Decision | Date |
| --- | --- | --- | --- |
| Business owner |  |  |  |
| Product manager |  |  |  |
| Design lead |  |  |  |
| Engineering lead |  |  |  |
