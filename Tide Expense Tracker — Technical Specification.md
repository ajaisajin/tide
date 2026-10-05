# Tide Expense Tracker — Technical Specification

Oct 5, 2026 · @Ajai

This spec turns the Doc into an engineering plan for the v1 build.

## Tech stack

One cross-platform codebase in Flutter, a managed Postgres backend in the Mumbai region, and on-device processing for anything that touches SMS, receipts or voice.

| Layer | Choice | Why |
| --- | --- | --- |
| Mobile framework | Flutter (Dart), single codebase for iOS and Android | Own rendering engine (Impeller) and GPU fragment shaders make the liquid Vessel feasible at 60–120 fps; one team ships both platforms |
| Animation | Custom fragment shaders + Rive for character motion (pebbles, ripples, droplet) | Shaders for the fluid surface; Rive for designer-authored, state-driven animations without code changes |
| State management | Riverpod | Testable, compile-safe dependency injection |
| Local database | SQLite via Drift | Offline-first, typed queries, migrations, reactive streams to drive the Vessel |
| Secure storage | iOS Keychain / Android Keystore (flutter\_secure\_storage) | Keys and tokens never stored in plain files |
| Backend platform | Supabase (PostgreSQL, Auth, Storage, Edge Functions), hosted in ap-south-1 (Mumbai) | Small backend team; Postgres with row-level security; data stays in India |
| Server logic | TypeScript Edge Functions (Deno) | Sync, pools settle-up, insights jobs, currency rates |
| Push notifications | Firebase Cloud Messaging (Android + APNs relay for iOS) | Single push pipeline for both platforms |
| On-device ML | Google ML Kit (Android), Apple Vision (iOS), platform speech recognisers | Receipts and voice processed on the phone; nothing sensitive leaves it |
| Analytics and crashes | Firebase Crashlytics + PostHog (self-hostable, event analytics) | Crash-free target and funnel tracking without selling data |
| CI/CD | GitHub Actions + Fastlane, Codemagic as alternative | Automated builds, tests and store uploads |

## Architecture

&#91;embedded content: system architecture · phone, cloud, third parties\]

SMS, receipts and voice are processed on the phone and only confirmed transactions sync; the cloud handles sign-in, multi-device sync, shared pools, push and currency rates.

## Mobile app

The app is a single Flutter project split into feature modules; the Vessel renderer is isolated so it can be tuned or swapped without touching business logic.

**Module structure**

| Module | Responsibility |
| --- | --- |
| core | Theme tokens, routing, DI, error handling, localisation (English, Hindi) |
| data | Drift database, repositories, sync engine, API client |
| vessel\_renderer | Liquid shader, gyroscope input, pebble physics, reduced-motion fallback |
| capture | Drop-to-log flow, amount ring, voice entry, receipt scan, SMS suggestions |
| budget | Budget, category limits, safe-to-spend calculation, rollover |
| river | Time River history, pinch zoom, search |
| goals | Goal Wells, surplus transfer |
| pools | Shared pools, splits, settle-up |
| notify | Local reminders, push handling, threshold alerts |
| settings | Account, security lock, export, skins, privacy controls |

**Vessel rendering**

- Liquid surface drawn by a GLSL fragment shader on a full-screen canvas; inputs are fill level (0–1), tilt vector, ripple impulses and a state colour.
- Tilt comes from the gyroscope/accelerometer via sensors\_plus, sampled at 60 Hz, low-pass filtered, and only while the Vessel is visible.
- Surface motion uses a damped spring model (1D wave across \~64 surface points) so a spend produces a visible drain and settle in \~600 ms.
- Pebbles are 2D rigid bodies with simple buoyancy; when a category exceeds its limit, buoyancy is reduced so it sinks.
- If frame time exceeds 20 ms for 2 seconds, the renderer drops to "still water" (flat animated level, no physics).

**Gestures**

| Gesture | Recogniser | Conflict rule |
| --- | --- | --- |
| Swipe down from top edge | Custom edge drag (top 48 dp) | Wins over system notification shade only inside the app's safe area |
| Spin amount ring | Rotational pan; ₹10 per step, accelerates with speed | Locks other gestures while ring is active |
| Flick drop onto pebble | Velocity-based hit-test toward nearest pebble | Snap if within 40 dp |
| Press-and-hold for Dial | Long press 350 ms | Cancels on movement > 10 dp before trigger |
| Pinch on Time River | Scale gesture with 4 zoom stops | — |
| Shake to undo | Accelerometer threshold 2.5 g for 300 ms | Disabled in reduced-motion mode; button fallback always shown |

Every gesture maps to a semantic action with an equivalent button for screen readers and switch access.

## Backend and APIs

The backend stores a synced copy of each user's data and runs the few jobs that need a server: sync, pools, notifications and rates. All endpoints are HTTPS, JSON, versioned under `/v1`, and authenticated with a short-lived JWT (15 min) plus refresh token.

**Services**

| Service | Runs as | Purpose |
| --- | --- | --- |
| Auth | Supabase Auth | Phone OTP, Google, Apple sign-in; guest-to-account upgrade |
| Sync | Edge Function | Push and pull of changed records per user |
| Pools | Edge Function + Postgres | Membership, shared expenses, balances, settle-up links |
| Notifications | Scheduled Edge Function + FCM | Bill reminders, threshold alerts, weekly insights |
| Insights | Nightly job | Week-over-week category comparisons, max 1 per day per user |
| Rates | Daily job | Currency rates cache for multi-currency entries |
| Export | Edge Function + Storage | Monthly PDF statement generated server-side, link expires in 24 h |
| Subscriptions | Store webhooks (Google Play, App Store) via RevenueCat | Tide Plus entitlement status |

**Endpoints (v1)**

| Method | Path | Purpose |
| --- | --- | --- |
| POST | /v1/sync/push | Upload local changes since last cursor |
| GET | /v1/sync/pull?cursor= | Download server changes since cursor |
| GET | /v1/me | Profile, settings, entitlement |
| PATCH | /v1/me | Update profile, currency, locale |
| POST | /v1/pools | Create a pool |
| POST | /v1/pools/{id}/invite | Create invite link (expires in 7 days) |
| POST | /v1/pools/{id}/join | Join with invite token |
| POST | /v1/pools/{id}/expenses | Add shared expense with split rule |
| GET | /v1/pools/{id}/balances | Who owes whom |
| POST | /v1/pools/{id}/settle | Generate UPI settle-up link and record settlement |
| POST | /v1/export | Request PDF statement for a month |
| GET | /v1/rates?base=INR | Cached currency rates |
| POST | /v1/devices | Register push token |
| DELETE | /v1/me | Delete account and all data (DPDP right to erasure) |

Personal transactions, budgets and categories go only through sync, not through per-record REST endpoints, which keeps the API small and the app fully offline-capable.

## Data model

The same schema exists in SQLite on the phone and Postgres on the server. Every synced table carries `id` (UUID v7, generated on device), `user_id`, `updated_at` (hybrid logical clock), `version` and `deleted` (soft delete). Money is stored as integer minor units (paise) plus a currency code — never floats.

| Table | Key columns | Notes |
| --- | --- | --- |
| users | id, name, phone, email, home\_currency, locale, monthly\_income\_minor, created\_at | Row-level security: user sees only own row |
| categories | id, user\_id, name, colour, icon, monthly\_limit\_minor, sort\_order | 10 defaults seeded on signup |
| transactions | id, user\_id, type (expense/income/transfer), amount\_minor, currency, home\_amount\_minor, category\_id, merchant, note, occurred\_at, source (manual/voice/sms/scan/recurring), pool\_id, receipt\_path | Indexed on (user\_id, occurred\_at) and (user\_id, category\_id) |
| budgets | id, user\_id, month (YYYY-MM), total\_minor, rollover\_rule (none/next\_month/goal) | One row per month |
| recurring\_rules | id, user\_id, amount\_minor, category\_id, rrule, next\_due\_at, auto\_log | RFC 5545 recurrence rule |
| goals | id, user\_id, name, target\_minor, target\_date, saved\_minor | — |
| goal\_transfers | id, goal\_id, amount\_minor, occurred\_at | Audit trail of surplus moved |
| merchant\_rules | id, user\_id, merchant\_pattern, category\_id, confirmations | Learns after 2 confirmations (FR-10) |
| pools | id, name, owner\_id, created\_at | Server-authoritative |
| pool\_members | pool\_id, user\_id, role, joined\_at | Max 6 members |
| pool\_expenses | id, pool\_id, paid\_by, amount\_minor, split\_rule (JSON), occurred\_at | Split rule: equal or custom shares |
| settlements | id, pool\_id, from\_user, to\_user, amount\_minor, upi\_ref, settled\_at | — |
| devices | id, user\_id, platform, push\_token, last\_seen\_at | — |

Raw SMS text is never stored in any table, on device or server; only the parsed fields of a confirmed transaction are saved.

## Offline and sync

The phone is the source of truth for personal data: every write lands in SQLite first (≤ 100 ms) and syncs in the background. Pools are the exception — the server is authoritative there because several people edit them.

**Sync cycle**

1. Each local write is saved and added to an outbox table with its hybrid-logical-clock timestamp.
2. When online, the sync worker sends outbox changes in batches of up to 200 to `/v1/sync/push`.
3. The server applies each change field by field; the newer timestamp wins (last-write-wins per field), so editing a note on one phone and an amount on another both survive.
4. The worker then calls `/v1/sync/pull` with its cursor and applies server changes locally.
5. The cursor advances only after the local transaction commits, so a crash mid-sync is safe to retry.

**Triggers**: app open, after each write (debounced 5 s), every 15 min while foreground, and a background fetch (WorkManager on Android, BGTaskScheduler on iOS) at least daily.

**Guest mode**: data stays local only; on sign-up the local records are pushed as the user's first sync.

**Deletes** are soft (`deleted = true`) and purged after 30 days, so they propagate to every device first.

## Integrations

All capture integrations run on the device; the server never sees raw SMS, receipt images (unless the user chooses to attach one) or audio.

| Integration | Platform | How it works | Fallback |
| --- | --- | --- | --- |
| Bank/UPI SMS capture | Android | Reads incoming SMS (with user consent) through a broadcast receiver; a rules engine of sender IDs and regex templates per bank extracts amount, debit/credit, merchant/VPA, date. Rules ship as a signed JSON file updated remotely without an app release | Notification listener on UPI app alerts; manual entry |
| Payment capture | iOS | iOS gives apps no SMS access; users share a payment message or receipt via the Share Sheet, or run a Tide Shortcut from an Automation | Manual entry |
| Receipt scan | Both | ML Kit Text Recognition (Android) / Vision (iOS) on-device; heuristics pick the total, date and merchant; user confirms | Manual entry |
| Voice entry | Both | Platform speech recogniser (on-device where supported) → local parser for amount, category keyword, note; English and Hindi | Typed entry |
| UPI settle-up | Both | Builds a `upi://pay` intent link with payee VPA, name, amount and note; opens the user's UPI app. Tide never handles money | Show VPA and amount to pay manually |
| In-app purchases | Both | Google Play Billing and StoreKit via RevenueCat SDK | — |
| Home-screen widget | Both | Android Glance widget, iOS WidgetKit; reads a small shared summary (level %, safe-to-spend) | — |

SMS parser target: ≥ 95% correct extraction on the top 20 Indian banks and UPI apps, measured on an anonymised test corpus before launch.

## Security, privacy and compliance

Financial data is encrypted on the phone, in transit and at rest on the server, and every user can export or delete everything.

| Area | Control |
| --- | --- |
| On-device storage | SQLite encrypted with SQLCipher (AES-256); key held in Keychain/Keystore |
| App lock | Face ID / fingerprint / PIN after 1 min in background (configurable); hide-amounts mode |
| Transport | TLS 1.3 only; certificate pinning on API host |
| Server storage | Postgres and Storage encrypted at rest; row-level security on every table keyed to `auth.uid()` |
| Auth | OTP rate limit 5 per hour per number; refresh-token rotation; sign out of all devices |
| Secrets | No keys in the app binary beyond public anon key; server secrets in the platform's vault |
| SMS permission | Requested only when the user turns on auto-capture, with an in-app explainer before the system prompt |
| Data residency | All data hosted in India (Mumbai region) |
| DPDP Act 2023 | Clear consent notice, purpose limitation, data export (CSV/JSON), account deletion within 30 days, grievance contact |
| Store policies | Google Play SMS/Call Log permission declaration form; Apple privacy nutrition labels and account-deletion requirement |
| Logging | No amounts, merchants or notes in logs or analytics events; analytics opt-out in settings |
| Testing | Third-party penetration test and OWASP MASVS L1 checklist before launch |

## Performance, testing and delivery

The build fails if the Vessel misses its frame budget on the reference low-end device, the same way it fails on a broken unit test.

**Performance budgets**

| Metric | Budget | Measured on |
| --- | --- | --- |
| Frame time, Vessel | ≤ 16.6 ms (60 fps); ≤ 8.3 ms on 120 Hz iOS | Reference Android with 4 GB RAM; iPhone 13 |
| Cold start to interactive | ≤ 1.5 s | Reference Android |
| Save an entry (local) | ≤ 100 ms | Both |
| Sync of 200 changes | ≤ 3 s on 4G | Both |
| Install size | ≤ 40 MB | Store listing |
| Battery | < 2% per day of normal use | 24-hour test script |

**Testing**

- Unit tests for budget maths, safe-to-spend, splits, SMS parser rules (target 80% coverage on core logic).
- Widget and golden-image tests for every screen in light, dark and reduced-motion modes.
- Integration tests on real devices via Firebase Test Lab (20 Android models) and an iOS device farm.
- Sync tests: two simulated devices editing the same records offline, then reconnecting.
- Usability tests: 15+ users per round on the gesture model (BRD usability gate).
- Accessibility audit: TalkBack and VoiceOver walkthrough of every flow.

**CI/CD and environments**

- Environments: dev, staging, production — separate Supabase projects.
- Every pull request: lint, tests, build, frame-time benchmark.
- Main branch: auto-build to internal testers (Play internal track, TestFlight).
- Releases: staged rollout 5% → 25% → 100% with crash-free gate of 99.5%.
- Feature flags for risky features (SMS capture, new skins) so they can be switched off without a release.

**Monitoring**

Crashlytics for crashes and ANRs, PostHog for funnels (time-to-log, D30 retention), Supabase logs and alerts for API error rate > 1% and sync latency.

## Open technical questions

- [ ] Confirm the Google Play SMS permission exception applies to Tide's use case; if refused, ship Android with notification-listener capture only.
- [ ] Prototype the liquid shader on the reference low-end Android in the first 2 weeks — go/no-go for Flutter vs a native renderer.
- [ ] Choose the OTP SMS provider with Indian DLT-registered sender ID and templates.
- [ ] Decide whether receipt images sync to the cloud (storage cost, privacy) or stay on device only.
- [ ] Pick the Hindi speech parsing approach: rule-based keywords vs an on-device small language model.
- [ ] Confirm RevenueCat vs direct store billing integration based on pricing at expected volume.
