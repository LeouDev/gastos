# gastos

Know where your money goes. A native iOS finance tracker built with SwiftUI, SwiftData, Swift Charts and WidgetKit. It stores data on the device first. Signing in is optional and turns on sync through Supabase.

## Run

Open `gastos.xcodeproj` in Xcode 26 and run the **gastos** scheme (iOS 26+).

- Tests: `⌘U`, or `xcodebuild -scheme gastos -destination 'platform=iOS Simulator,name=iPhone 17e' test`. This runs the unit tests for the money rules (`gastosTests`) and UI tests that drive onboarding, adding an expense, and paying a credit card (`gastosUITests`). UI tests launch the app with `-uiTesting`, which gives each test a fresh in-memory store and clean settings.
- Demo data (Debug only): turn on the `-sampleData` launch argument in the scheme. It uses an in-memory store and never touches real data.
- Deep links: `gastos://add/expense`, `gastos://add/income`, `gastos://add/transfer`

## How the money works

All the rules live in `Shared/Finance.swift`, and `gastosTests/FinanceTests.swift` tests them.

- **Expense**: money leaves a wallet and counts as spending.
- **Income**: money enters a wallet.
- **Transfer**: money moves between two wallets. It never counts as spending or income.
- **Credit card**: a wallet whose balance goes negative when you owe money. A purchase on the card is an expense. Paying the card is a transfer, so the same money is never counted twice.
- **Balances** are calculated from each wallet's opening balance plus its transactions, so edits and deletes can't make them drift.
- **You can spend**: total money minus the recurring bills due before the next payday (the next recurring income), divided by the days until then. With no payday set, it runs to the end of the month.
- **Totals** include only wallets in the main currency. There is no currency conversion.

## Layout

```
Shared/            models, finance engine, theme (compiled into app + widget)
gastos/App         app entry, lock, tabs, shortcuts, debug sample data
gastos/Components  design-system views (cards, chips, bars, rows)
gastos/Services    app lock, recurring posting, first-launch seed
gastos/Features    Home, Transactions, Wallets, AddTransaction, Insights, Budgets, Recurring, Settings, Onboarding
gastosWidget/      home-screen widget (total money, safe to spend, quick add)
gastosTests/       Swift Testing suite for the financial rules
gastosUITests/     XCUITest end-to-end flows
```

## Sync (Supabase)

Syncing is optional. In Settings, **Sign in with Apple** turns it on. With no account, everything stays on the device and works offline.

- **Local store:** SwiftData is always what the UI reads.
- **Push:** `SyncService` (`gastos/Services/Sync.swift`) reads local changes from SwiftData history, so cascaded deletes are included. It upserts them to Supabase and sends deletes as `deleted = true` tombstones.
- **Pull:** it fetches rows whose server-side `updated_at` is newer than the last pull. The last write wins.
- **When it runs:** on app open, when the app goes to the background, on pull-to-refresh, and from **Sync now** in Settings.
- **Server security:** tables `accounts`, `categories`, `entries`, `budgets` and `recurring_transactions` all have row-level security, so each user sees only their own rows. There is no DELETE policy, because deletes are tombstones.
- **Account deletion:** the `delete_my_account()` RPC removes the auth user, which deletes all of their rows.
- **Money:** amounts are Postgres `numeric` and travel as text, so no `Double` ever touches them.

**One-time setup (Supabase dashboard):** go to Authentication → Sign In / Providers → Apple, enable it, and add `com.leoudev.gastos` under Client IDs.

## Signing

Team `Z5643XKUTZ`. The capabilities are the app group `group.com.leoudev.gastos` (shared with the widget) and Sign in with Apple. Xcode's automatic signing needs your Apple account under Xcode → Settings → Accounts.

## TestFlight

**One-time setup in App Store Connect:** go to Apps → **+** → New App.
- **Platform:** iOS
- **Bundle ID:** `com.leoudev.gastos`
- **SKU:** any unique text, e.g. `gastos-ios`
- **Name:** App Store names are unique, so plain "gastos" may be taken. Try something like "gastos — money tracker".

**Upload a build:**

```sh
scripts/testflight.sh
```

Each run archives a Release build with a timestamp build number and uploads it. Builds show up under TestFlight after processing.

- **Internal testers:** up to 100 people on your App Store Connect team. No review needed.
- **External testers:** up to 10,000, invited by email or a public link. Needs a one-time Beta App Review, a beta description, and a privacy policy URL. Use [PRIVACY.md](PRIVACY.md): <https://github.com/LeouDev/gastos/blob/main/PRIVACY.md>.
