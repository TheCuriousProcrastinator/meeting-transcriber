@testable import MeetingTranscriber
import XCTest

@MainActor
final class LiveCaptionRollupTests: XCTestCase {
    func testShortHypothesisUsesOneVisualLine() {
        let state = LiveCaptionsState()
        state.applyPartial(
            "hello there",
            channel: .mic
        )

        let lines = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].speaker, "Me")
        XCTAssertTrue(lines[0].showsSpeaker)
        XCTAssertEqual(lines[0].text, "hello there")
    }

    func testLongHypothesisKeepsOnlyNewestFourLines() {
        let state = LiveCaptionsState()
        state.setSize(.small)

        let body = (1...180)
            .map { "word\($0)" }
            .joined(separator: " ")
            + " TAILMARKER"

        state.applyPartial(
            body,
            channel: .mic
        )

        let lines = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(
            lines.count,
            LiveCaptionRollup.maxVisibleLines
        )

        XCTAssertTrue(
            lines.last?.text.contains("TAILMARKER")
                == true,
            "the newest words must remain visible"
        )
    }

    func testSpeakerMovesToFirstRemainingLineAfterRoll() {
        let state = LiveCaptionsState()
        state.setSize(.small)

        state.applyPartial(
            (1...180)
                .map { "word\($0)" }
                .joined(separator: " "),
            channel: .mic
        )

        let lines = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].showsSpeaker)

        XCTAssertTrue(
            lines.dropFirst().allSatisfy {
                !$0.showsSpeaker
            }
        )
    }

    func testWordUpdatesDoNotChangeVisualLineIdentity() {
        let state = LiveCaptionsState()
        state.setSize(.large)

        state.applyPartial(
            "hello",
            channel: .mic
        )

        let before = LiveCaptionRollup.visibleLines(
            from: state
        )

        state.applyPartial(
            "hello how are you",
            channel: .mic
        )

        let after = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(
            before.map(\.id),
            after.map(\.id),
            "word-level partials on the same visual line "
                + "must not retrigger the roll animation"
        )
    }

    func testFourLineAreaFitsEveryPresetPanel() {
        for size in LiveCaptionsSize.allCases {
            let captionHeight =
                LiveCaptionRollup.captionAreaHeight(
                    for: size
                )

            XCTAssertLessThan(
                captionHeight,
                size.panelSize.height,
                "\(size) must leave room for the backend "
                    + "label and vertical padding"
            )
        }
    }

    func testMatchedNameKeepsTheSameVisualIdentity() {
        let state = LiveCaptionsState()
        state.setSize(.large)

        state.applyPartial(
            "I think we should move this to next week",
            channel: .app,
            utteranceID: 42
        )

        let partial = LiveCaptionRollup.visibleLines(
            from: state
        )

        state.applyFinalized(
            "I think we should move this to next week",
            channel: .app,
            speaker: "Remote",
            utteranceID: 42
        )

        state.updateSpeaker(
            "David",
            channel: .app,
            utteranceID: 42
        )

        let matched = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(
            partial.map(\.id),
            matched.map(\.id),
            "speaker recognition must not create a fake roll"
        )
        XCTAssertEqual(matched.first?.speaker, "David")
    }

    func testConsecutiveSameSpeakerLabelsOnlyFirstLine() {
        let state = LiveCaptionsState()
        state.setSize(.large)

        state.applyFinalized(
            "First sentence.",
            channel: .app,
            speaker: "David",
            utteranceID: 1
        )

        state.applyFinalized(
            "Second sentence.",
            channel: .app,
            speaker: "David",
            utteranceID: 2
        )

        let lines = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].showsSpeaker)
        XCTAssertFalse(lines[1].showsSpeaker)
    }

    func testSpeakerChangeStartsFreshLabeledLine() {
        let state = LiveCaptionsState()
        state.setSize(.large)

        state.applyFinalized(
            "First speaker.",
            channel: .app,
            speaker: "David",
            utteranceID: 1
        )

        state.applyFinalized(
            "Second speaker.",
            channel: .app,
            speaker: "Rob",
            utteranceID: 2
        )

        let lines = LiveCaptionRollup.visibleLines(
            from: state
        )

        XCTAssertEqual(
            lines.map(\.speaker),
            ["David", "Rob"]
        )
        XCTAssertEqual(
            lines.map(\.showsSpeaker),
            [true, true]
        )
    }

}
