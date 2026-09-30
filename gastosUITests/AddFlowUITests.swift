import XCTest

/// Drives the real app on a fresh in-memory store (`-uiTesting`), from onboarding onward.
final class AddFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// The core promise: ₱350 → Food → GCash → done, and Home reflects it.
    func testAddExpenseFromHome() {
        onboard(wallets: ["GCash": "5000"])
        XCTAssertTrue(element(containing: "Total money", "5,000").waitForExistence(timeout: 5))

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Expense"].tap()
        app.textFields["Amount"].typeText("350")
        app.buttons["Food"].tap()
        app.buttons["GCash"].tap()
        app.buttons["Add Expense"].tap()

        XCTAssertTrue(element(containing: "Total money", "4,650").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Spent", "350").exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Food'")).firstMatch.exists)
    }

    /// Card purchase is spending; paying the card is a transfer and must not count again.
    func testCreditCardPaymentIsNotSpending() {
        onboard(wallets: ["BPI Savings": "10000", "Credit Card": ""])

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Expense"].tap()
        app.textFields["Amount"].typeText("2000")
        app.buttons["Groceries"].tap()
        app.buttons["Credit Card"].tap()
        app.buttons["Add Expense"].tap()

        XCTAssertTrue(element(containing: "Spent", "2,000").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Total money", "8,000").exists)

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Transfer"].tap()
        app.textFields["Amount"].typeText("2000")
        app.buttons["BPI Savings"].firstMatch.tap()                  // From
        app.buttons.matching(identifier: "Credit Card").element(boundBy: 1).tap()  // To
        app.buttons["Transfer"].tap()

        XCTAssertTrue(app.textFields["Amount"].waitForNonExistence(timeout: 5), "transfer sheet should close")
        XCTAssertTrue(element(containing: "Total money", "8,000").exists)
        XCTAssertTrue(element(containing: "Spent", "2,000").exists)
        XCTAssertFalse(element(containing: "Spent", "4,000").exists)

        // The money actually moved: bank down, card paid off.
        app.buttons["Wallets"].firstMatch.tap()
        XCTAssertTrue(element(containing: "BPI Savings", "8,000").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Credit Card", "₱0").exists)
    }

    /// Rejects an empty amount instead of saving a ₱0 expense.
    func testEmptyAmountIsRejected() {
        onboard(wallets: ["Cash": "100"])
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Expense"].tap()
        app.buttons["Add Expense"].tap()
        XCTAssertTrue(app.staticTexts["Enter an amount"].waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private func onboard(wallets: [String: String]) {
        app.buttons["Continue"].tap()
        for (name, balance) in wallets {
            app.buttons[name].tap()
            if !balance.isEmpty {
                let field = app.textFields["\(name) balance"]
                field.tap()
                field.typeText(balance)
            }
        }
        app.buttons["Continue"].tap()
        app.buttons["Start"].tap()
    }

    private func element(containing parts: String...) -> XCUIElement {
        let format = parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND ")
        return app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: parts)).firstMatch
    }
}
