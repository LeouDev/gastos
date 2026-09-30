import XCTest

/// A paced walkthrough for the App Review video (`scripts/review-video.sh` records it).
/// Fresh install, subscription required: onboarding → paywall → subscribe (local test store) → core features.
final class ReviewWalkthroughUITests: XCTestCase {
    func testWalkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-paywall", "-appearance", "light"]
        app.launch()
        pause(5)  // welcome animation
        waitForIntro(app)

        // Onboarding: pick wallets with starting balances.
        app.buttons["Continue"].tap(); pause()
        for (name, balance) in [("GCash", "5000"), ("Cash", "1500")] {
            app.buttons[name].tap(); pause(0.6)
            let field = app.textFields["\(name) balance"]
            field.tap(); field.typeText(balance); pause(0.6)
        }
        app.swipeDown(); pause()
        app.buttons["Continue"].tap(); pause()
        app.buttons["Start"].tap(); pause(3)

        // Paywall: subscribe (₱99/month; code GASTOS gives the first month free).
        let subscribe = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Premium'")).firstMatch
        XCTAssertTrue(subscribe.waitForExistence(timeout: 10))
        pause(3)
        subscribe.tap(); pause(3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Subscribe"].waitForExistence(timeout: 3) { springboard.buttons["Subscribe"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.935)).tap() }
        for label in ["OK", "Done"] where springboard.buttons[label].waitForExistence(timeout: 3) { springboard.buttons[label].tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        pause(3)

        // Add an expense: ₱350, Food, GCash.
        app.buttons["Add"].firstMatch.tap(); pause()
        app.buttons["choose.expense"].tap(); pause()
        app.textFields["Amount"].typeText("350"); pause()
        app.buttons["Food"].tap(); pause()
        app.buttons["GCash"].firstMatch.tap(); pause()
        let what = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Lunch'")).firstMatch
        if what.exists { what.tap(); what.typeText("Lunch"); pause() }
        app.buttons["entry.submit"].tap(); pause(3)

        // A transfer: Cash → GCash (not counted as spending).
        app.buttons["Add"].firstMatch.tap(); pause()
        app.buttons["choose.transfer"].tap(); pause()
        app.textFields["Amount"].typeText("500"); pause()
        app.buttons["Cash"].firstMatch.tap(); pause()
        app.buttons.matching(identifier: "GCash").element(boundBy: 1).tap(); pause()
        app.buttons["entry.submit"].tap(); pause(3)

        // Where did it go → which wallet paid.
        app.swipeUp(); pause(2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Food'")).firstMatch.tap(); pause(3)
        app.navigationBars.buttons.firstMatch.tap(); pause()
        app.swipeDown(); pause()

        app.tabBars.buttons["Transactions"].firstMatch.tap(); pause(3)

        app.tabBars.buttons["Wallets"].firstMatch.tap(); pause(2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'GCash card'")).firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap(); pause(3)
        app.navigationBars.buttons.firstMatch.tap(); pause()

        app.tabBars.buttons["Insights"].firstMatch.tap(); pause(3)

        // Settings: subscription management, sync (optional account, with Delete account once signed in), app lock.
        app.tabBars.buttons["Home"].firstMatch.tap(); pause()
        app.buttons["Settings"].tap(); pause(2)
        app.swipeUp(); pause(3)
        app.swipeUp(); pause(3)
    }

    private func pause(_ seconds: Double = 1.2) { Thread.sleep(forTimeInterval: seconds) }
}
