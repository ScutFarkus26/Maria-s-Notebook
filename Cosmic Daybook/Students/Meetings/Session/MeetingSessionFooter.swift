import SwiftUI
import CoreData

/// Pinned under the form so Complete is always in reach (⌘↩). Drafts save on
/// their own, so the footer says so instead of offering Save Draft.
struct MeetingSessionFooter: View {
    let isEmpty: Bool
    let savedAt: Date?
    let decided: Int
    let decisionsTotal: Int
    let completeLabel: String
    var onSkip: (() -> Void)?
    let onComplete: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                status
                Spacer(minLength: 8)
                buttons(fillWidth: false)
            }
            VStack(spacing: 8) {
                status
                buttons(fillWidth: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        #if os(iOS)
        // The floating quick-capture button (56 pt, 24 pt in from the edge)
        // sits over the footer's trailing corner; keep Complete out from under it.
        .padding(.trailing, 64)
        #endif
    }

    private var status: some View {
        HStack(spacing: 6) {
            Image(systemName: savedAt == nil ? "circle.dashed" : "checkmark.circle")
                .foregroundStyle(savedAt == nil ? Color.secondary : AppColors.success)
            Text(statusText)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        var parts = [savedAt == nil ? (isEmpty ? "Nothing written yet" : "Saving…") : "Draft saved"]
        if decisionsTotal > 0 {
            parts.append("\(decided) of \(decisionsTotal) decision\(decisionsTotal == 1 ? "" : "s") made")
        }
        return parts.joined(separator: " · ")
    }

    private func buttons(fillWidth: Bool) -> some View {
        HStack(spacing: 8) {
            if let onSkip {
                // Narrow footers (a phone) make Skip a plain text button so
                // Complete keeps its one line.
                if fillWidth {
                    Button("Skip", action: onSkip)
                        .buttonStyle(.borderless)
                        .help("Move on and keep this draft")
                } else {
                    Button("Skip for Now", action: onSkip)
                        .buttonStyle(.bordered)
                        .help("Move on and keep this draft")
                }
            }
            Button(action: onComplete) {
                Text(completeLabel)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: fillWidth ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isEmpty)
            .help("\(completeLabel) (⌘↩)")
        }
        .controlSize(.large)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Phone decision pager

/// On a phone, one stuck work item at a time, with Next to move along.
struct CompactDecisionPager: View {
    let stuck: [CDWorkModel]
    @Bindable var draft: MeetingDraftModel
    let workTitle: (CDWorkModel) -> String

    @State private var index = 0

    private var decided: Int {
        stuck.filter { $0.id.map(draft.reviewedWorkIDs.contains) ?? false }.count
    }

    var body: some View {
        let work = stuck[index % stuck.count]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Needs a Decision · \(decided) of \(stuck.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if stuck.count > 1 {
                    Button("Next") {
                        adaptiveWithAnimation { index = (index + 1) % stuck.count }
                    }
                    .font(.subheadline)
                }
            }
            WorkDecisionCard(work: work, title: workTitle(work), draft: draft)
                .id(work.objectID)
        }
    }
}
