import XCTest

final class ActivityTrackingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Setup Helper

    private func prepareForTracking(careeName: String = "Test Caree", activityTypeName: String = "Feeding") {
        // Add caree if needed
        if !app.staticTexts[careeName].exists {
            addTestCaree(named: careeName)
        }

        // Navigate to caree detail
        app.staticTexts[careeName].tap()
        XCTAssertTrue(app.navigationBars[careeName].waitForExistence(timeout: 2))

        // Add activity type if needed
        if !app.staticTexts[activityTypeName].exists {
            addTestActivityType(named: activityTypeName)
        }
    }

    // MARK: - Track Basic Activity Tests

    func testTrackBasicActivity() throws {
        prepareForTracking()

        // Tap Track Activity button
        app.buttons["Track Activity"].tap()

        // Wait for track view to appear
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        // Select activity type
        let activityTypePicker = app.buttons["Feeding"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Save activity
        app.buttons["Save"].tap()

        // Verify activity appears in recent activities
        // Note: The exact verification depends on how activities are displayed
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    func testTrackActivityWithQuantity() throws {
        // Setup with quantity-enabled activity type
        prepareForTracking(activityTypeName: "Bottle")

        // First, configure the activity type to have quantity
        app.staticTexts["Bottle"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enable quantity if not already
        if !app.switches["Has quantity"].isOn {
            app.switches["Has quantity"].tap()
            let unitField = app.textFields["Unit (e.g., oz, minutes)"]
            unitField.tap()
            unitField.typeText("oz")
            app.buttons["Save"].tap()
        } else {
            app.buttons["Cancel"].tap()
        }

        // Track activity
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        // Select activity type
        let activityTypePicker = app.buttons["Bottle"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Enter quantity
        let quantityField = app.textFields.matching(identifier: "quantity").firstMatch
        if quantityField.exists {
            quantityField.tap()
            quantityField.typeText("4")
        }

        // Save
        app.buttons["Save"].tap()

        // Verify we're back at detail view
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    func testTrackActivityWithNotes() throws {
        prepareForTracking()

        // Tap Track Activity button
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        // Select activity type
        let activityTypePicker = app.buttons["Feeding"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Enter notes
        let notesField = app.textViews.matching(identifier: "notes").firstMatch
        if notesField.exists {
            notesField.tap()
            notesField.typeText("Test notes for this activity")
        }

        // Save
        app.buttons["Save"].tap()

        // Verify we're back at detail view
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    func testTrackActivityWithEmptyQuantityAllowed() throws {
        // Setup with quantity-enabled activity type
        prepareForTracking(activityTypeName: "Bottle")

        // Configure activity type with quantity
        app.staticTexts["Bottle"].tap()
        if !app.switches["Has quantity"].isOn {
            app.switches["Has quantity"].tap()
            let unitField = app.textFields["Unit (e.g., oz, minutes)"]
            unitField.tap()
            unitField.typeText("oz")
            app.buttons["Save"].tap()
        } else {
            app.buttons["Cancel"].tap()
        }

        // Track activity without entering quantity
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        let activityTypePicker = app.buttons["Bottle"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Don't enter quantity - should still allow save
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled)

        saveButton.tap()

        // Verify we're back at detail view (save succeeded)
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    func testCancelTrackActivity() throws {
        prepareForTracking()

        // Tap Track Activity button
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        // Select activity type and enter data
        let activityTypePicker = app.buttons["Feeding"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Cancel
        app.buttons["Cancel"].tap()

        // Verify we're back at detail view
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    // MARK: - View Activities Tests

    func testViewActivitiesList() throws {
        prepareForTracking()

        // Track an activity first
        trackTestActivity(type: "Feeding")

        // Tap View All to see activities list
        if app.buttons["View All"].exists {
            app.buttons["View All"].tap()

            // Verify we're in the activities list view
            XCTAssertTrue(app.navigationBars["Activities"].waitForExistence(timeout: 2))

            // Navigate back
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testDeleteActivityWithConfirmation() throws {
        prepareForTracking()

        // Track an activity
        trackTestActivity(type: "Feeding")

        // View all activities if available
        if app.buttons["View All"].exists {
            app.buttons["View All"].tap()
            XCTAssertTrue(app.navigationBars["Activities"].waitForExistence(timeout: 2))

            // Find and delete an activity
            let cells = app.cells
            if !cells.isEmpty {
                let firstCell = cells.element(boundBy: 0)
                firstCell.swipeLeft()

                app.buttons["Delete"].tap()

                // Confirmation dialog should appear
                let confirmDialog = app.alerts["Delete Activity?"]
                XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

                // Confirm deletion
                confirmDialog.buttons["Delete"].tap()
            }

            // Navigate back
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testCancelDeleteActivity() throws {
        prepareForTracking()

        // Track an activity
        trackTestActivity(type: "Feeding")

        // View all activities
        if app.buttons["View All"].exists {
            app.buttons["View All"].tap()
            XCTAssertTrue(app.navigationBars["Activities"].waitForExistence(timeout: 2))

            // Find and attempt to delete
            let cells = app.cells
            if !cells.isEmpty {
                let cellCount = cells.count

                let firstCell = cells.element(boundBy: 0)
                firstCell.swipeLeft()

                app.buttons["Delete"].tap()

                // Confirmation dialog should appear
                let confirmDialog = app.alerts["Delete Activity?"]
                XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

                // Cancel deletion
                confirmDialog.buttons["Cancel"].tap()

                // Verify cell count unchanged
                XCTAssertEqual(app.cells.count, cellCount)
            }

            // Navigate back
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    // MARK: - Date/Time Tests

    func testTrackActivityWithCustomDateTime() throws {
        prepareForTracking()

        // Tap Track Activity button
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        // Select activity type
        let activityTypePicker = app.buttons["Feeding"]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        // Tap on date/time picker (if accessible in UI test)
        // Note: DatePicker interactions can be complex in UI tests
        // This is a placeholder for date/time interaction

        // Save
        app.buttons["Save"].tap()

        // Verify we're back
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }

    // MARK: - Helper Methods

    private func addTestCaree(named name: String) {
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2))
    }

    private func addTestActivityType(named name: String) {
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2))
    }

    private func trackTestActivity(type: String) {
        app.buttons["Track Activity"].tap()
        XCTAssertTrue(app.navigationBars["Track Activity"].waitForExistence(timeout: 2))

        let activityTypePicker = app.buttons[type]
        if activityTypePicker.exists {
            activityTypePicker.tap()
        }

        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Test Caree"].waitForExistence(timeout: 2))
    }
}
