@testable import MeetingTranscriber
import XCTest

final class LiveCaptionsShortcutTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()

        suiteName =
            "LiveCaptionsShortcutTests-\(getpid())-\(UUID().uuidString)"

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }

        self.defaults = defaults
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultShortcutIsControlOptionT() {
        let settings = makeSettings()

        XCTAssertEqual(
            settings.liveCaptionsShortcut,
            GlobalShortcut.defaultLiveCaptions
        )
        XCTAssertEqual(
            settings.liveCaptionsShortcut?.displayString,
            "⌃⌥T"
        )
    }

    func testCustomShortcutPersistsAcrossSettingsInstances() {
        let settings = makeSettings()
        let custom = GlobalShortcut(
            keyCode: 11,
            modifiers: 4096 | 512,
            keyLabel: "B"
        )

        settings.liveCaptionsShortcut = custom

        XCTAssertEqual(
            makeSettings().liveCaptionsShortcut,
            custom
        )
    }

    func testClearedShortcutRemainsDisabledAfterReload() {
        let settings = makeSettings()

        settings.liveCaptionsShortcut = nil

        XCTAssertNil(makeSettings().liveCaptionsShortcut)
    }

    func testShowingLiveCaptionsArmsPipelineAndPersistsVisibility() {
        let settings = makeSettings()
        settings.liveTranscriptionEnabled = false
        settings.liveCaptionsOverlayEnabled = false

        settings.setShowLiveCaptions(true)

        let reloaded = makeSettings()
        XCTAssertTrue(reloaded.liveTranscriptionEnabled)
        XCTAssertTrue(reloaded.liveCaptionsOverlayEnabled)
        XCTAssertTrue(reloaded.showLiveCaptions)
    }

    func testHidingLiveCaptionsLeavesPipelineArmed() {
        let settings = makeSettings()
        settings.setShowLiveCaptions(true)

        settings.setShowLiveCaptions(false)

        XCTAssertTrue(settings.liveTranscriptionEnabled)
        XCTAssertFalse(settings.liveCaptionsOverlayEnabled)
        XCTAssertFalse(settings.showLiveCaptions)
    }

    func testShortcutOverlayTogglePersistsForNextMeeting() {
        let settings = makeSettings()
        settings.setShowLiveCaptions(true)

        settings.toggleLiveCaptionsOverlayPreference()

        let hiddenReload = makeSettings()
        XCTAssertTrue(hiddenReload.liveTranscriptionEnabled)
        XCTAssertFalse(hiddenReload.liveCaptionsOverlayEnabled)
        XCTAssertFalse(hiddenReload.showLiveCaptions)

        hiddenReload.toggleLiveCaptionsOverlayPreference()

        let shownReload = makeSettings()
        XCTAssertTrue(shownReload.liveTranscriptionEnabled)
        XCTAssertTrue(shownReload.liveCaptionsOverlayEnabled)
        XCTAssertTrue(shownReload.showLiveCaptions)
    }

    private func makeSettings() -> AppSettings {
        AppSettings(
            defaults: defaults,
            apiKeyAccount:
                "LiveCaptionsShortcutTests-openai-\(suiteName!)",
            claudeAPIKeyAccount:
                "LiveCaptionsShortcutTests-claude-\(suiteName!)"
        )
    }
}
