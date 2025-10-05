import XCTest

final class CareeManagementUITests: XCTestCase {
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

    // MARK: - Add Caree Tests

    func testAddCaree() throws {
        // Tap the add button
        app.buttons["Add"].tap()

        // Wait for the sheet to appear
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Name field should be auto-focused
        XCTAssertTrue(nameField.hasFocus)

        // Enter caree name
        nameField.tap()
        nameField.typeText("Test Caree")

        // Save button should be enabled
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled)

        // Tap save
        saveButton.tap()

        // Verify caree appears in list
        XCTAssertTrue(app.staticTexts["Test Caree"].waitForExistence(timeout: 2))
    }

    func testAddCareeWithEmptyName() throws {
        // Tap the add button
        app.buttons["Add"].tap()

        // Wait for the sheet to appear
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Save button should be disabled with empty name
        let saveButton = app.buttons["Save"]
        XCTAssertFalse(saveButton.isEnabled)
    }

    func testCancelAddCaree() throws {
        // Tap the add button
        app.buttons["Add"].tap()

        // Wait for the sheet to appear
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Enter some text
        nameField.tap()
        nameField.typeText("Cancelled Caree")

        // Tap cancel
        app.buttons["Cancel"].tap()

        // Verify caree was not added
        XCTAssertFalse(app.staticTexts["Cancelled Caree"].exists)
    }

    // MARK: - Edit Caree Tests

    func testEditCaree() throws {
        // First add a caree
        addTestCaree(named: "Original Name")

        // Tap on the caree to open detail view
        app.staticTexts["Original Name"].tap()

        // Tap Edit button
        app.buttons["Edit"].tap()

        // Wait for edit sheet
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Clear and update name
        nameField.tap()
        nameField.doubleTap() // Select all
        nameField.typeText("Updated Name")

        // Save changes
        app.buttons["Save"].tap()

        // Verify updated name appears
        XCTAssertTrue(app.navigationBars["Updated Name"].waitForExistence(timeout: 2))
    }

    func testCancelEditCaree() throws {
        // First add a caree
        addTestCaree(named: "Original Name")

        // Tap on the caree to open detail view
        app.staticTexts["Original Name"].tap()

        // Tap Edit button
        app.buttons["Edit"].tap()

        // Wait for edit sheet
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        // Change name but cancel
        nameField.tap()
        nameField.doubleTap()
        nameField.typeText("Cancelled Edit")

        // Cancel changes
        app.buttons["Cancel"].tap()

        // Verify original name remains
        XCTAssertTrue(app.navigationBars["Original Name"].exists)
        XCTAssertFalse(app.navigationBars["Cancelled Edit"].exists)
    }

    // MARK: - Delete Caree Tests

    func testDeleteCareeWithConfirmation() throws {
        // First add a caree
        addTestCaree(named: "To Be Deleted")

        // Navigate back to list
        if app.buttons["Carees"].exists {
            app.buttons["Carees"].tap()
        } else if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // Swipe to delete
        let careeCell = app.staticTexts["To Be Deleted"]
        careeCell.swipeLeft()

        // Tap delete button
        app.buttons["Delete"].tap()

        // Confirmation dialog should appear
        let confirmDialog = app.alerts["Delete Caree?"]
        XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

        // Confirm deletion
        confirmDialog.buttons["Delete"].tap()

        // Verify caree is deleted
        XCTAssertFalse(app.staticTexts["To Be Deleted"].exists)
    }

    func testCancelDeleteCaree() throws {
        // First add a caree
        addTestCaree(named: "Not Deleted")

        // Navigate back to list
        if app.buttons["Carees"].exists {
            app.buttons["Carees"].tap()
        } else if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // Swipe to delete
        let careeCell = app.staticTexts["Not Deleted"]
        careeCell.swipeLeft()

        // Tap delete button
        app.buttons["Delete"].tap()

        // Confirmation dialog should appear
        let confirmDialog = app.alerts["Delete Caree?"]
        XCTAssertTrue(confirmDialog.waitForExistence(timeout: 2))

        // Cancel deletion
        confirmDialog.buttons["Cancel"].tap()

        // Verify caree still exists
        XCTAssertTrue(app.staticTexts["Not Deleted"].exists)
    }

    // MARK: - Helper Methods

    private func addTestCaree(named name: String) {
        app.buttons["Add"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))

        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()

        // Wait for sheet to dismiss and caree to appear
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2))
    }
}
