import XCTest

/// With the subscription required (`-paywall`), onboarding lands on a locked paywall; buying through the
/// local StoreKit test store (the scheme's Products.storekit) unlocks the app.
/// Run it with the unit tests: `SubscriptionProductTests` sets up and empties the simulator's test store first.
final class PaywallUITests: XCTestCase {
    func testPaywallLocksUntilSubscribed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-paywall"]
        app.launch()
        waitForIntro(app)
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Start"].tap()

        guard app.staticTexts["Know where your money goes."].waitForExistence(timeout: 10) else {
            if app.tabBars.firstMatch.exists { throw XCTSkip("Already subscribed in the test store; run with the unit tests, which reset it.") }
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "no-paywall"; shot.lifetime = .keepAlways; add(shot)
            return XCTFail("Paywall never appeared")
        }
        XCTAssertTrue(app.buttons["Redeem a code. Enter the GASTOS code first for 1 month free."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "paywall"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "the app must stay locked until subscribed")

        let subscribe = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Subscribe' OR label CONTAINS[c] 'Premium'")).firstMatch
        XCTAssertTrue(subscribe.waitForExistence(timeout: 10))
        subscribe.tap()
        // StoreKit's confirmation sheet is drawn by another process: look there, or tap its button's spot.
        sleep(3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let sheetButton = springboard.buttons["Subscribe"]
        if sheetButton.waitForExistence(timeout: 3) {
            sheetButton.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.935)).tap()
        }
        for label in ["OK", "Done"] where springboard.buttons[label].waitForExistence(timeout: 3) {
            springboard.buttons[label].tap()
        }

        if !app.tabBars.firstMatch.waitForExistence(timeout: 15) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after-subscribe"; shot.lifetime = .keepAlways; add(shot)
            XCTFail("subscribing should unlock the app")
        }
    }
}
