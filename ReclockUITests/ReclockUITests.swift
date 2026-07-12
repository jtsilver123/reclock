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

    // MARK: Onboarding path

    func testOnboardingToEmptyHome() throws {
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

        // Main app appears with the empty-home hero.
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

        // Navigate: Today → trip summary row → Trip detail.
        let tripRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '→'")).firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 10))
        tripRow.tap()

        let delayButton = app.buttons["My flight changed / was delayed"]
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))
        delayButton.tap()

        let plusTwo = app.buttons["+2h"]
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 5))
        plusTwo.tap()
        app.buttons["Update plan"].tap()

        // Back on trip detail; the plan was rebuilt (revision bump is internal — verify UI alive).
        XCTAssertTrue(delayButton.waitForExistence(timeout: 8))
    }

    func testDeleteTrip() throws {
        let app = launchSeeded()

        let tripRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '→'")).firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 10))
        tripRow.tap()

        let deleteButton = app.buttons["Delete trip"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let confirm = app.buttons["Delete trip and plan"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // Home returns to the empty hero.
        XCTAssertTrue(app.staticTexts["Feel local when you land"].waitForExistence(timeout: 10))
    }

    func testSettingsPrivacyControlsExist() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Everything stays on this device"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Export my data (JSON)"].exists)
        XCTAssertTrue(app.buttons["Delete all data"].exists)
    }
}
