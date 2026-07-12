import XCTest

/// Critical-path UI tests. The app runs with `-reclock-uitest` (isolated store, mock
/// services) and optionally `-reclock-seed-demo` (a landing-day demo trip preloaded).
final class ReclockUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-reclock-uitest", "-reclock-seed-demo"]
        app.launch()
        return app
    }

    /// Scrolls until the element is hittable — content below the fold exists in the
    /// hierarchy but can't be tapped (and List rows may not materialize) until visible.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    // MARK: Onboarding path

    func testOnboardingLeadsStraightIntoAddTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reclock-uitest"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
        app.buttons["Add my trip"].firstMatch.tap()

        // Sleep basics → plane sleep → plan style → preferences → finish.
        for _ in 0..<4 {
            let continueButton = app.buttons["Continue"].firstMatch
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
            continueButton.tap()
        }
        let finish = app.buttons["Add my trip"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        // "Add my trip" does what it says: the add-trip sheet opens immediately.
        XCTAssertTrue(app.navigationBars["Add a trip"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()

        // Dismissing lands on the empty-home hero with tabs alive.
        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    // MARK: Active-trip path

    func testSeededTripShowsPlanAndCompletesAction() throws {
        let app = launchSeeded()

        // Landing-day demo: either a Now card with Done, or the quiet card.
        let done = app.buttons["Done"].firstMatch
        let quiet = app.staticTexts["Nothing to do right now"]
        let hasContent = done.waitForExistence(timeout: 12) || quiet.waitForExistence(timeout: 4)
        XCTAssertTrue(hasContent, "Home should show a Now card or the quiet state")

        if done.exists {
            done.tap()
            // The action completes; home remains functional.
            XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        }
    }

    func testTimelineShowsPhases() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Timeline"].tap()

        // Phase headers from the demo trip.
        let anyPhase = app.staticTexts["After arrival"].waitForExistence(timeout: 10)
            || app.staticTexts["In flight"].exists
            || app.staticTexts["Before departure"].exists
            || app.staticTexts["Recovery days"].exists
        XCTAssertTrue(anyPhase, "Timeline should show phase headers")
    }

    func testReportDelayFlow() throws {
        let app = launchSeeded()

        // Navigate: Today → trip card (below the fold on landing day) → Trip detail.
        let tripCard = app.buttons["home.tripCard"]
        XCTAssertTrue(tripCard.waitForExistence(timeout: 10))
        scrollTo(tripCard, in: app)
        tripCard.tap()

        let delayButton = app.buttons["My flight changed / was delayed"]
        XCTAssertTrue(delayButton.waitForExistence(timeout: 8))
        scrollTo(delayButton, in: app)
        delayButton.tap()

        let plusTwo = app.buttons["+2h"]
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 8))
        scrollTo(plusTwo, in: app)
        plusTwo.tap()
        app.buttons["Update plan"].tap()

        // Back on trip detail; the plan was rebuilt (revision bump is internal — verify UI alive).
        XCTAssertTrue(delayButton.waitForExistence(timeout: 10))
    }

    func testDeleteTrip() throws {
        let app = launchSeeded()

        let tripCard = app.buttons["home.tripCard"]
        XCTAssertTrue(tripCard.waitForExistence(timeout: 10))
        scrollTo(tripCard, in: app)
        tripCard.tap()

        let deleteButton = app.buttons["Delete trip"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 8))
        scrollTo(deleteButton, in: app)
        deleteButton.tap()

        let confirm = app.buttons["Delete trip and plan"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()

        // Home returns to the empty hero.
        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
    }

    func testSettingsPrivacyControlsExist() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Everything stays on this device"].waitForExistence(timeout: 8))
        // Privacy rows sit below the fold; List rows materialize on scroll.
        let export = app.buttons["Export my data (JSON)"]
        scrollTo(export, in: app)
        XCTAssertTrue(export.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Delete all data"].exists)
    }
}
