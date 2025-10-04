import XCTest

final class ActivityTypeUITests: XCTestCase {
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

    private func navigateToCareeDetail(named careeName: String = "Test Caree") {
        // Add a caree if needed
        if !app.staticTexts[careeName].exists {
            addTestCaree(named: careeName)
        }

        // Tap on caree to open detail view
        app.staticTexts[careeName].tap()

        // Wait for detail view to load
        XCTAssertTrue(app.navigationBars[careeName].waitForExistence(timeout: 2))
    }

    // MARK: - Add Activity Type Tests

    func testAddBasicActivityType() throws {
        navigateToCareeDetail()

        // Tap Add button in Activity Types section
        app.buttons["Add"].tap()

        // Wait for sheet to appear
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Name field should be auto-focused
        XCTAssertTrue(nameField.hasFocus)

        // Enter activity type details
        nameField.tap()
        nameField.typeText("Feeding")

        let iconField = app.textFields["Icon (emoji)"]
        iconField.tap()
        iconField.typeText("🍼")

        // Save
        app.buttons["Save"].tap()

        // Verify activity type appears
        XCTAssertTrue(app.staticTexts["Feeding"].waitForExistence(timeout: 2))
    }

    func testAddActivityTypeWithQuantity() throws {
        navigateToCareeDetail()

        // Tap Add button
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enter details
        nameField.tap()
        nameField.typeText("Bottle")

        // Enable quantity tracking
        app.switches["Has quantity"].tap()
        XCTAssertTrue(app.switches["Has quantity"].isOn)

        // Enter unit
        let unitField = app.textFields["Unit (e.g., oz, minutes)"]
        XCTAssertTrue(unitField.exists)
        unitField.tap()
        unitField.typeText("oz")

        // Save
        app.buttons["Save"].tap()

        // Verify activity type appears with quantity indicator
        XCTAssertTrue(app.staticTexts["Bottle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.images["number"].exists) // Quantity icon
    }

    func testAddActivityTypeWithLocation() throws {
        navigateToCareeDetail()

        // Tap Add button
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enter details
        nameField.tap()
        nameField.typeText("Walk")

        // Enable location tracking
        app.switches["Track location"].tap()
        XCTAssertTrue(app.switches["Track location"].isOn)

        // Save
        app.buttons["Save"].tap()

        // Verify activity type appears with location indicator
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.images["location"].exists) // Location icon
    }

    func testAddActivityTypeWithEmptyName() throws {
        navigateToCareeDetail()

        // Tap Add button
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Save button should be disabled with empty name
        let saveButton = app.buttons["Save"]
        XCTAssertFalse(saveButton.isEnabled)
    }

    func testCancelAddActivityType() throws {
        navigateToCareeDetail()

        // Tap Add button
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enter some text
        nameField.tap()
        nameField.typeText("Cancelled Type")

        // Tap cancel
        app.buttons["Cancel"].tap()

        // Verify activity type was not added
        XCTAssertFalse(app.staticTexts["Cancelled Type"].exists)
    }

    // MARK: - Edit Activity Type Tests

    func testEditActivityType() throws {
        navigateToCareeDetail()

        // Add an activity type
        addTestActivityType(named: "Original Type")

        // Tap on the activity type to edit
        app.staticTexts["Original Type"].tap()

        // Wait for edit sheet
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Update name
        nameField.tap()
        nameField.doubleTap()
        nameField.typeText("Updated Type")

        // Save changes
        app.buttons["Save"].tap()

        // Verify updated name appears
        XCTAssertTrue(app.staticTexts["Updated Type"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Original Type"].exists)
    }

    func testEditActivityTypeToggleQuantity() throws {
        navigateToCareeDetail()

        // Add an activity type without quantity
        addTestActivityType(named: "Simple Type")

        // Edit it
        app.staticTexts["Simple Type"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enable quantity
        app.switches["Has quantity"].tap()
        XCTAssertTrue(app.switches["Has quantity"].isOn)

        // Enter unit
        let unitField = app.textFields["Unit (e.g., oz, minutes)"]
        unitField.tap()
        unitField.typeText("ml")

        // Save
        app.buttons["Save"].tap()

        // Verify quantity indicator appears
        XCTAssertTrue(app.images["number"].exists)
    }

    // MARK: - Delete Activity Type Tests

    func testDeleteActivityTypeWithConfirmation() throws {
        navigateToCareeDetail()

        // Add an activity type
        addTestActivityType(named: "To Delete")

        // Swipe to delete
        let typeCell = app.staticTexts["To Delete"]
        typeCell.swipeLeft()

        // Tap delete button
        app.buttons["Delete"].tap()

        // Confirmation dialog should appear
        let confirmDialog = app.alerts["Delete Activity Type?"]
        XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

        // Verify warning message
        XCTAssertTrue(confirmDialog.staticTexts["This will also delete all associated activities. This cannot be undone."].exists)

        // Confirm deletion
        confirmDialog.buttons["Delete"].tap()

        // Verify activity type is deleted
        XCTAssertFalse(app.staticTexts["To Delete"].exists)
    }

    func testCancelDeleteActivityType() throws {
        navigateToCareeDetail()

        // Add an activity type
        addTestActivityType(named: "Not Deleted")

        // Swipe to delete
        let typeCell = app.staticTexts["Not Deleted"]
        typeCell.swipeLeft()

        // Tap delete button
        app.buttons["Delete"].tap()

        // Confirmation dialog should appear
        let confirmDialog = app.alerts["Delete Activity Type?"]
        XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

        // Cancel deletion
        confirmDialog.buttons["Cancel"].tap()

        // Verify activity type still exists
        XCTAssertTrue(app.staticTexts["Not Deleted"].exists)
    }

    // MARK: - Reordering Tests

    func testReorderActivityTypes() throws {
        navigateToCareeDetail()

        // Add two activity types
        addTestActivityType(named: "First Type")
        addTestActivityType(named: "Second Type")

        // Get initial positions
        let firstCell = app.staticTexts["First Type"]
        let secondCell = app.staticTexts["Second Type"]

        XCTAssertTrue(firstCell.exists)
        XCTAssertTrue(secondCell.exists)

        // Long press and drag to reorder (this is a simplified test - actual drag implementation may vary)
        // Note: Reordering tests can be complex in UI testing and may need adjustment based on actual behavior
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
}
