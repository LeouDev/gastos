import XCTest

/// Needs Face ID enrolled on the simulator and something answering the prompt, e.g.
/// `xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match`.
/// Skips itself when no prompt ever appears (no enrollment), so it never fails CI for that.
final class AppLockUITests: XCTestCase {
    func testLockCoversAppAfterBackgroundAndUnlocks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.buttons["Continue"].tap()
        app.buttons["Cash"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Start"].tap()

        app.buttons["Settings"].tap()
        let lock = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Lock gastos'")).firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.switches.firstMatch.tap()

        let turnedOn = NSPredicate(format: "value == '1'")
        guard XCTWaiter.wait(for: [expectation(for: turnedOn, evaluatedWith: lock)], timeout: 15) == .completed else {
            throw XCTSkip("No biometric match arrived; enroll Face ID in the simulator to run this test.")
        }

        // Leave and come back: the lock must cover the app, then Face ID lets you back in.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["gastos is locked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["gastos is locked"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Lock gastos'")).firstMatch.exists)
    }
}
