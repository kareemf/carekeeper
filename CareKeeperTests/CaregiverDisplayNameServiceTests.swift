@testable import CareKeeper
import XCTest

@MainActor
final class CaregiverDisplayNameServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var service: CaregiverDisplayNameService!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.kareemf.CareKeeperTests.CaregiverDisplayName.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        service = CaregiverDisplayNameService(testing: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        service = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - resolvedDisplayName

    func testResolvedDisplayNameReturnsNameWhenSet() {
        service.displayName = "Sarah"
        XCTAssertEqual(service.resolvedDisplayName, "Sarah")
    }

    func testResolvedDisplayNameReturnsFallbackWhenNil() {
        service.displayName = nil
        XCTAssertEqual(service.resolvedDisplayName, "A caregiver")
    }

    func testResolvedDisplayNameReturnsFallbackForEmptyString() {
        service.displayName = ""
        XCTAssertEqual(service.resolvedDisplayName, "A caregiver")
    }

    func testResolvedDisplayNameReturnsFallbackForWhitespaceOnly() {
        service.displayName = "   \t\n  "
        XCTAssertEqual(service.resolvedDisplayName, "A caregiver")
    }

    // MARK: - hasDisplayName

    func testHasDisplayNameIsFalseWhenNil() {
        service.displayName = nil
        XCTAssertFalse(service.hasDisplayName)
    }

    func testHasDisplayNameIsFalseForEmptyString() {
        service.displayName = ""
        XCTAssertFalse(service.hasDisplayName)
    }

    func testHasDisplayNameIsFalseForWhitespaceOnly() {
        service.displayName = "   "
        XCTAssertFalse(service.hasDisplayName)
    }

    func testHasDisplayNameIsTrueWhenSet() {
        service.displayName = "Alex"
        XCTAssertTrue(service.hasDisplayName)
    }

    // MARK: - shouldPromptForDisplayName

    func testShouldPromptForDisplayNameIsTrueInitially() {
        XCTAssertTrue(service.shouldPromptForDisplayName)
    }

    func testShouldPromptForDisplayNameIsFalseAfterMarkPrompted() {
        service.markPrompted()
        XCTAssertFalse(service.shouldPromptForDisplayName)
    }

    func testShouldPromptForDisplayNameIsFalseWhenNameIsSet() {
        service.displayName = "Jordan"
        XCTAssertFalse(service.shouldPromptForDisplayName)
    }

    // MARK: - Persistence

    func testDisplayNamePersistsToUserDefaults() {
        service.displayName = "Taylor"
        let stored = defaults.string(forKey: "caregiverDisplayName")
        XCTAssertEqual(stored, "Taylor")
    }

    func testMarkPromptedPersistsToUserDefaults() {
        service.markPrompted()
        XCTAssertTrue(defaults.bool(forKey: "caregiverDisplayNamePrompted"))
    }

    func testInitLoadsExistingDisplayName() {
        defaults.set("Existing Name", forKey: "caregiverDisplayName")
        let freshService = CaregiverDisplayNameService(testing: defaults)
        XCTAssertEqual(freshService.displayName, "Existing Name")
        XCTAssertEqual(freshService.resolvedDisplayName, "Existing Name")
    }
}
