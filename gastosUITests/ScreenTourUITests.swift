import XCTest

/// Walks every screen with demo data (`-sampleData`) and attaches a screenshot of each.
/// Export: `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
/// Doubles as a source for App Store screenshots.
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-sampleData"]
        app.launch()
    }

    func testTour() {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        shot("01 Home")
        app.scrollViews.firstMatch.swipeLeft()  // next card in the carousel
        shot("01b Home next card")
        app.swipeUp()
        shot("02 Home scrolled")

        tab("Transactions"); shot("03 Transactions")

        tab("Wallets"); shot("04 Wallets")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'GCash'")).firstMatch.tap()
        shot("05 Wallet detail")
        app.buttons["Edit"].tap()
        app.buttons["Card Style"].tap(); shot("06 Card style")
        app.buttons["Cancel"].tap()

        tab("Insights"); shot("07 Insights")
        app.swipeUp(); shot("08 Insights scrolled")

        tab("Home")
        app.buttons["Settings"].tap(); shot("09 Settings")
        app.buttons["Budgets"].tap(); shot("10 Budgets")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Recurring"].tap(); shot("11 Recurring")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Netflix'")).firstMatch.tap()
        shot("12 Recurring editor")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Categories"].tap(); shot("13 Categories")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Food'")).firstMatch.tap()
        shot("14 Category editor")
        app.buttons["Cancel"].tap()

        for type in ["Expense", "Income", "Transfer"] {
            app.buttons["Add"].firstMatch.tap()
            if type == "Expense" { shot("15 What happened") }
            app.buttons["choose.\(type.lowercased())"].tap()
            shot("16 Add \(type)")
            app.buttons["Cancel"].tap()
        }
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
    }

    private func shot(_ name: String) {
        sleep(1)  // let transitions and bars finish animating
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
