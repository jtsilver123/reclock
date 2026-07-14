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
            // Generous: the first post-install run on a cold CI simulator can jank.
            XCTAssertTrue(continueButton.waitForExistence(timeout: 12))
            continueButton.tap()
        }
        // The optional sign-in step: sync-only, and skippable — the test skips.
        let skip = app.buttons["Skip for now"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        skip.tap()

        let finish = app.buttons["Add my trip"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 12))
        finish.tap()

        // "Add my trip" does what it says: the add-trip sheet opens immediately.
        XCTAssertTrue(app.navigationBars["Add a trip"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()

        // Dismissing lands on the empty-plan hero with tabs alive.
        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Trips"].exists)
    }

    // MARK: Plan tab

    func testSeededTripShowsPlanAndCompletesAction() throws {
        let app = launchSeeded()

        // Landing-day demo: the pinned header shows a Now card with Done, or the quiet card.
        let done = app.buttons["Done"].firstMatch
        let quiet = app.staticTexts["Nothing to do right now"]
        let hasContent = done.waitForExistence(timeout: 12) || quiet.waitForExistence(timeout: 4)
        XCTAssertTrue(hasContent, "Plan tab should show a Now card or the quiet state")

        if done.exists {
            done.tap()
            // The action completes; the Plan tab remains functional.
            XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 5))
        }
    }

    func testPlanShowsPhases() throws {
        let app = launchSeeded()

        // The full plan scrolls beneath the pinned header, grouped by phase.
        func anyPhaseVisible() -> Bool {
            app.staticTexts["After arrival"].exists
                || app.staticTexts["In flight"].exists
                || app.staticTexts["Before departure"].exists
                || app.staticTexts["Recovery days"].exists
        }
        let appeared = app.staticTexts["After arrival"].waitForExistence(timeout: 10) || anyPhaseVisible()
        if !appeared {
            app.swipeUp()
        }
        XCTAssertTrue(anyPhaseVisible(), "Plan tab should show phase headers in the scrolling plan")
    }

    // MARK: Trips tab

    func testReportDelayFlow() throws {
        let app = launchSeeded()

        // Navigate: Trips tab → the trip's row → Trip detail.
        app.tabBars.buttons["Trips"].tap()
        let row = app.buttons["trips.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // Trip detail is a List: rows below the fold do not exist in the hierarchy
        // until scrolled to — scroll FIRST, then assert. (Asserting existence before
        // scrolling is exactly how these tests failed on CI.)
        let delayButton = app.buttons["My flight changed / was delayed"]
        scrollTo(delayButton, in: app)
        XCTAssertTrue(delayButton.waitForExistence(timeout: 8))
        delayButton.tap()

        // "Flight changed" sheet: pick a common delay, apply it.
        XCTAssertTrue(app.navigationBars["Flight changed"].waitForExistence(timeout: 8))
        let plusTwo = app.buttons["+2h"]
        scrollTo(plusTwo, in: app)
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 8))
        plusTwo.tap()
        let update = app.buttons["Update plan"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        update.tap()

        // The sheet dismisses once the plan is rebuilt.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: update)
        waitForExpectations(timeout: 10)
        // Back on trip detail (scroll position preserved, so the row is still there).
        XCTAssertTrue(delayButton.waitForExistence(timeout: 10))
    }

    func testDeleteTrip() throws {
        let app = launchSeeded()

        app.tabBars.buttons["Trips"].tap()
        let row = app.buttons["trips.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // "Delete trip" is the last List section — scroll first (see testReportDelayFlow).
        let deleteButton = app.buttons["Delete trip"]
        scrollTo(deleteButton, in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 8))
        deleteButton.tap()

        let confirm = app.buttons["Delete trip and plan"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()

        // Back on the Trips tab, now empty.
        XCTAssertTrue(app.staticTexts["No trips yet"].waitForExistence(timeout: 10))

        // And the Plan tab returns to the empty hero.
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
    }

    // MARK: Settings tab

    func testSettingsPrivacyControlsExist() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()

        // Backup & sync sits above privacy; the label needs scrolling into existence.
        let privacyLabel = app.staticTexts["Everything stays on this device"]
        scrollTo(privacyLabel, in: app, maxSwipes: 9)
        XCTAssertTrue(privacyLabel.waitForExistence(timeout: 8))
        // Privacy rows sit below the fold; List rows materialize on scroll.
        let export = app.buttons["Export my data (JSON)"]
        scrollTo(export, in: app, maxSwipes: 9)
        XCTAssertTrue(export.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Delete all data"].exists)
    }
}
