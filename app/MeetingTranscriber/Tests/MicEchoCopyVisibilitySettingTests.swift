@testable import MeetingTranscriber
import ViewInspector
import XCTest

@MainActor
final class MicEchoCopyVisibilitySettingTests: XCTestCase {
    private func freshSettings() -> AppSettings {
        let defaults = UserDefaults(
            suiteName:
                "mic-echo-copy-visibility-\(UUID().uuidString)"
        )!
        // swiftlint:disable:previous force_unwrapping
        return AppSettings(defaults: defaults)
    }

    func testVisibilityDefaultsOn() {
        XCTAssertTrue(
            freshSettings().hideLikelyMicEchoCopies
        )
    }

    func testVisibilityChoicePersists() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(
                suiteName:
                    "mic-echo-copy-persist-\(UUID().uuidString)"
            )
        )

        let settings = AppSettings(defaults: defaults)
        settings.hideLikelyMicEchoCopies = false

        XCTAssertFalse(
            AppSettings(defaults: defaults)
                .hideLikelyMicEchoCopies
        )
    }

    func testVisibilityToggleWritesBackToSettings() throws {
        let settings = freshSettings()
        let before = settings.hideLikelyMicEchoCopies

        let view = AudioSettingsView(settings: settings)

        let toggle = try view.inspect().find(
            viewWithAccessibilityIdentifier:
                A11yID.hideLikelyMicEchoCopiesToggle
        )

        try toggle.find(ViewType.Toggle.self).tap()

        XCTAssertEqual(
            settings.hideLikelyMicEchoCopies,
            !before
        )
    }
}
