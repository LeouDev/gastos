import XCTest

/// Each card in the stack opens itself when you tap its visible strip, even under photo cards.
final class WalletStackUITests: XCTestCase {
    func testEveryCardStripOpensItsOwnWallet() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData"]
        app.launch()
        app.tabBars.buttons["Wallets"].firstMatch.tap()

        for name in ["BPI Savings", "GCash", "Cash", "BPI Credit Card"] {
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + " card")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), name)
            // Tap the top strip, the only part of a stacked card you can see.
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "Tapping \(name) opened something else")
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testLongPressAndDragMovesACard() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData"]
        app.launch()
        app.tabBars.buttons["Wallets"].firstMatch.tap()

        func card(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + " card")).firstMatch
        }
        XCTAssertTrue(card("Cash").waitForExistence(timeout: 5))
        XCTAssertLessThan(card("BPI Savings").frame.minY, card("Cash").frame.minY)

        let from = card("Cash").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let to = card("BPI Savings").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        from.press(forDuration: 1.0, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.6)

        // Cash is now the top card.
        let moved = NSPredicate { _, _ in card("Cash").frame.minY < card("BPI Savings").frame.minY }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 5), .completed)
    }
}
