import XCTest

/// App Store screenshots from demo data. Run on a 6.9" simulator (iPhone 17 Pro Max) and export the
/// attachments; `scripts/app-store-screenshots.sh` does both and frames them.
final class AppStoreScreenshotsUITests: XCTestCase {
    func testScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))

        shot(app, "1-home")

        // Add an expense: ₱350, Food, GCash.
        app.buttons["Add"].firstMatch.tap()
        app.buttons["choose.expense"].tap()
        app.textFields["Amount"].typeText("350")
        app.buttons["Food"].tap()
        app.buttons["GCash"].firstMatch.tap()
        shot(app, "2-add")
        app.buttons["Cancel"].tap()

        // Where did it go → a category's wallets.
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Food'")).firstMatch.tap()
        shot(app, "3-category")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Wallets"].firstMatch.tap()
        shot(app, "4-wallets")

        app.tabBars.buttons["Insights"].firstMatch.tap()
        shot(app, "5-insights")

        app.tabBars.buttons["Wallets"].firstMatch.tap()
        app.swipeUp()
        // Tap the Suki card's visible strip; its middle sits under the next card.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Suki'")).firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        shot(app, "6-pass")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(2)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
