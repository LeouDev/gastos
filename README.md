# gastos

Know where your money goes. A native iOS finance tracker built with SwiftUI, SwiftData, Swift Charts and WidgetKit. It stores data on the device first and syncs through iCloud.

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

## iCloud & signing

The app uses the iCloud container `iCloud.com.leoudev.gastos` and the app group `group.com.leoudev.gastos` under team `Z5643XKUTZ`. The first time you run it on a real device, Xcode's automatic signing registers both of these. `ModelConfiguration(cloudKitDatabase: .automatic)` falls back to local-only storage if iCloud isn't available.
