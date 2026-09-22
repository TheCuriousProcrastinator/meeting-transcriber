import SwiftUI

/// Four-line roll-up caption bar.
///
/// Live ASR hypotheses may update several times per second. Those word-level
/// changes replace text in place and do not animate. Only a change in visual
/// line identity animates, so a newly wrapped line rolls in from the bottom
/// while the oldest visible line leaves through the top.
///
/// The caption area always reserves four rows. That keeps the surrounding
/// panel and background stationary while speech grows.
///
/// The system Reduce Motion preference replaces positional movement with a
/// short opacity transition.
struct LiveCaptionsOverlay: View {
    @Bindable var state: LiveCaptionsState

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        let lines = state.hasContent
            ? LiveCaptionRollup.visibleLines(from: state)
            : []

        VStack {
            Spacer(minLength: 0)

            if state.hasContent {
                TimelineView(.periodic(from: .now, by: 0.2)) {
                    context in
                    content(lines: lines)
                        .opacity(
                            state.opacity(at: context.date)
                        )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottom
        )
        .animation(
            .easeOut(
                duration: reduceMotion ? 0.12 : 0.18
            ),
            value: lines.map(\.id)
        )
    }

    private func content(
        lines: [LiveCaptionRollup.VisualLine]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let backend = state.activeBackend {
                Text(backend)
                    .font(
                        .system(
                            size: state.size.labelFontSize,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.45)
                    )
                    .accessibilityIdentifier(
                        A11yID.liveCaptionBackend
                    )
            }

            VStack(
                alignment: .leading,
                spacing: LiveCaptionRollup.rowSpacing
            ) {
                Spacer(minLength: 0)

                ForEach(lines) { line in
                    visualLine(line)
                        .transition(
                            transitionForLine
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: LiveCaptionRollup.captionAreaHeight(
                    for: state.size
                ),
                maxHeight: LiveCaptionRollup.captionAreaHeight(
                    for: state.size
                ),
                alignment: .bottomLeading
            )
            .clipped()
        }
        .font(
            .system(
                size: state.size.fontSize,
                weight: .medium,
                design: .rounded
            )
        )
        .multilineTextAlignment(.leading)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            .black.opacity(0.55),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .shadow(
            color: .black.opacity(0.25),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    private func visualLine(
        _ line: LiveCaptionRollup.VisualLine
    ) -> some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: LiveCaptionRollup.speakerSpacing
        ) {
            Text(line.speaker + ":")
                .fontWeight(.semibold)
                .foregroundStyle(
                    .white.opacity(
                        line.showsSpeaker
                            ? min(line.opacity, 0.85)
                            : 0
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(
                    width: line.speakerColumnWidth,
                    alignment: .trailing
                )

            Text(line.text)
                .foregroundStyle(
                    .white.opacity(line.opacity)
                )
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }

    private var transitionForLine: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion:
                .move(edge: .bottom)
                .combined(with: .opacity),
            removal:
                .move(edge: .top)
                .combined(with: .opacity)
        )
    }
}
