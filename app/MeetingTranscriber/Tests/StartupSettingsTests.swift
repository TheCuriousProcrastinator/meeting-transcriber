import ServiceManagement
@testable import MeetingTranscriber
import XCTest

final class StartupSettingsTests: XCTestCase {
    func testLaunchAtLoginToggleReflectsServiceStatus() {
        XCTAssertFalse(
            GeneralSettingsView.launchAtLoginToggleValue(
                for: .notRegistered
            )
        )
        XCTAssertTrue(
            GeneralSettingsView.launchAtLoginToggleValue(
                for: .enabled
            )
        )
        XCTAssertTrue(
            GeneralSettingsView.launchAtLoginToggleValue(
                for: .requiresApproval
            )
        )
        XCTAssertFalse(
            GeneralSettingsView.launchAtLoginToggleValue(
                for: .notFound
            )
        )
    }
}
