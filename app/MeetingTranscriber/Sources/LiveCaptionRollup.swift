import AppKit
import Foundation

/// Converts live captions into a fixed four-line roll-up.
///
/// Word-level partial updates retain their visual IDs, so they replace text
/// without animation. Only a genuinely new wrapped line or utterance gets a
/// new identity and participates in the roll transition.
enum LiveCaptionRollup {
    static let maxVisibleLines = 4

    static let horizontalPadding: CGFloat = 24
    static let rowSpacing: CGFloat = 4
    static let speakerSpacing: CGFloat = 8

    struct VisualLine: Identifiable, Equatable {
        let id: String
        let sourceID: String
        let speaker: String
        let speakerColumnWidth: CGFloat
        let text: String
        let opacity: Double
        var showsSpeaker: Bool
    }

    private struct SourceRow {
        let id: String
        let speaker: String
        let text: String
        let opacity: Double
    }

    @MainActor
    static func visibleLines(
        from state: LiveCaptionsState,
        maxLines: Int = maxVisibleLines
    ) -> [VisualLine] {
        guard maxLines > 0 else {
            return []
        }

        var rows: [SourceRow] = []

        for index in state.recentFinals.indices {
            let line = state.recentFinals[index]

            let utteranceID =
                state.recentFinalIDs.indices.contains(index)
                ? state.recentFinalIDs[index]
                : UInt64(index)

            rows.append(
                SourceRow(
                    id:
                        "utterance-"
                        + line.channel.rawValue
                        + "-"
                        + String(utteranceID),
                    speaker: line.speaker,
                    text: line.text,
                    opacity: 1.0
                )
            )
        }

        if !state.hypothesisApp.isEmpty {
            let id = state.hypothesisAppID
                .map { "utterance-app-\($0)" }
                ?? "hypothesis-app"

            rows.append(
                SourceRow(
                    id: id,
                    speaker: state.appLabel,
                    text: state.hypothesisApp,
                    opacity: 0.6
                )
            )
        }

        if !state.hypothesisMic.isEmpty {
            let id = state.hypothesisMicID
                .map { "utterance-mic-\($0)" }
                ?? "hypothesis-mic"

            rows.append(
                SourceRow(
                    id: id,
                    speaker: state.micLabel,
                    text: state.hypothesisMic,
                    opacity: 0.6
                )
            )
        }

        let totalWidth = max(
            1,
            state.size.panelSize.width
                - 2 * horizontalPadding
        )

        let allLines = rows.flatMap {
            wrap(
                row: $0,
                totalWidth: totalWidth,
                fontSize: state.size.fontSize
            )
        }

        var visible =
            Array(allLines.suffix(maxLines))

        // A visible speaker label marks a speaker turn, not every ASR chunk.
        // If the top of a turn rolled away, its first remaining line becomes
        // the label carrier.
        var previousSpeaker: String?

        for index in visible.indices {
            let speaker = visible[index].speaker

            visible[index].showsSpeaker =
                previousSpeaker == nil
                || previousSpeaker != speaker

            previousSpeaker = speaker
        }

        return visible
    }

    static func captionAreaHeight(
        for size: LiveCaptionsSize,
        maxLines: Int = maxVisibleLines
    ) -> CGFloat {
        guard maxLines > 0 else {
            return 0
        }

        let font = NSFont.systemFont(
            ofSize: size.fontSize,
            weight: .medium
        )

        let lineHeight = ceil(
            font.ascender
                - font.descender
                + font.leading
        )

        return lineHeight * CGFloat(maxLines)
            + rowSpacing * CGFloat(maxLines - 1)
    }

    private static func wrap(
        row: SourceRow,
        totalWidth: CGFloat,
        fontSize: CGFloat
    ) -> [VisualLine] {
        let text = row.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return []
        }

        let bodyFont = NSFont.systemFont(
            ofSize: fontSize,
            weight: .medium
        )

        // Fixed column means Remote -> David cannot alter the body width
        // and cause a fake re-wrap / roll animation.
        let speakerWidth =
            ceil(fontSize * 6.0)

        let bodyWidth = max(
            40,
            totalWidth
                - speakerWidth
                - speakerSpacing
        )

        let storage = NSTextStorage(
            attributedString: NSAttributedString(
                string: text,
                attributes: [.font: bodyFont]
            )
        )

        let layoutManager = NSLayoutManager()

        let textContainer = NSTextContainer(
            size: CGSize(
                width: bodyWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        )

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(
            for: textContainer
        )

        guard glyphRange.length > 0 else {
            return [
                VisualLine(
                    id: row.id + "-0",
                    sourceID: row.id,
                    speaker: row.speaker,
                    speakerColumnWidth: speakerWidth,
                    text: text,
                    opacity: row.opacity,
                    showsSpeaker: true
                ),
            ]
        }

        let nsText = text as NSString
        var result: [VisualLine] = []

        layoutManager.enumerateLineFragments(
            forGlyphRange: glyphRange
        ) { _, _, _, lineGlyphRange, _ in
            let characterRange =
                layoutManager.characterRange(
                    forGlyphRange: lineGlyphRange,
                    actualGlyphRange: nil
                )

            guard
                characterRange.location != NSNotFound,
                characterRange.location
                    + characterRange.length
                    <= nsText.length
            else {
                return
            }

            let lineText =
                nsText.substring(
                    with: characterRange
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !lineText.isEmpty else {
                return
            }

            let lineIndex = result.count

            result.append(
                VisualLine(
                    id: row.id + "-\(lineIndex)",
                    sourceID: row.id,
                    speaker: row.speaker,
                    speakerColumnWidth: speakerWidth,
                    text: lineText,
                    opacity: row.opacity,
                    showsSpeaker: lineIndex == 0
                )
            )
        }

        return result
    }
}
