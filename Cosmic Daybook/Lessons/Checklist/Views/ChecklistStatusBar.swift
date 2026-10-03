//
//  ChecklistStatusBar.swift
//  Cosmic Daybook
//
//  The strip under the checklist grid: the ladder's key with live counts over the
//  rows and students on screen, on one short line. While the Ready lens is on, the
//  rule a ringed cell meets sits on its own line above the key and wraps where the
//  window is narrow, so the key keeps its full width. Its items sit at the leading
//  end; the trailing end lies under the app's floating + button, which the grid
//  clears with a bottom content margin instead (`gridBottomMargin`).
//

import SwiftUI

struct ChecklistStatusBar: View {
    let counts: ChecklistStatusCounts
    let lessonCount: Int
    let studentCount: Int
    /// Under the Ready lens the bar adds a line above the key with the rule a ringed cell
    /// meets, and the key's other marks fade as the grid's do.
    var lens: ChecklistLens = .allMarks

    /// The floating button's trailing footprint: 56 pt wide, 24 pt from the edge, plus a gap.
    private static let floatingButtonClearance: CGFloat = 92
    private static let markSize: CGFloat = 13
    static let height: CGFloat = 32

    /// How far the grid's content scrolls past its last row, so that row can rise above
    /// the floating button: on the Mac the button reaches 80 pt above the window's bottom,
    /// on iPad 104; on iPhone the tab bar already takes most of it. Less this bar's height,
    /// plus a gap.
    static func gridBottomMargin(isRegular: Bool) -> CGFloat {
        #if os(macOS)
        return 80 - height + 8
        #else
        return isRegular ? 104 - height + 8 : 60 - height + 8
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lens == .ready {
                readyRule
            }
            key
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checklist key")
    }

    /// The ladder's marks with their counts, one line that scrolls sideways if it must.
    private var key: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(ChecklistDisplayStatus.allCases, id: \.self) { status in
                    legendItem(label: status.label, count: counts[status], help: Self.meaning(of: status)) {
                        ChecklistMark(
                            status: status, size: Self.markSize,
                            emphasizesReady: lens == .ready && status == .ready
                        )
                        .opacity(lens == .ready && status != .ready ? ChecklistLens.fadedOpacity : 1)
                    }
                }
                legendItem(
                    label: "Needs a check-in", count: counts.needsCheckIn,
                    help: "Open work nobody has touched in about three weeks"
                ) {
                    ChecklistCheckInDot(size: Self.markSize)
                        .opacity(lens == .ready ? ChecklistLens.fadedOpacity : 1)
                }
                Text("over \(Self.counted(lessonCount, "lesson")) × \(Self.counted(studentCount, "student"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.leading, 12)
            .padding(.trailing, Self.floatingButtonClearance)
            .frame(height: Self.height)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
    }

    /// The Ready lens's rule on its own line, wrapping rather than pushing the key off
    /// the screen; it stops short of the floating button like the key does.
    private var readyRule: some View {
        Label(ChecklistLens.readyRule, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.trailing, Self.floatingButtonClearance)
            .padding(.top, 7)
            .help("Practice and the guide's confirmation count where the sequence asks for them")
    }

    private func legendItem<Mark: View>(
        label: String, count: Int, help: String, @ViewBuilder mark: () -> Mark
    ) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(label)
                .font(.caption)
            Text(count, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// The legend's hover text: what puts a cell on each rung.
    private static func meaning(of status: ChecklistDisplayStatus) -> String {
        switch status {
        case .notReady: return "Not presented, and the lesson before still holds it back"
        case .ready: return "Not presented or planned, and nothing holds it back"
        case .planned: return "In the Inbox or on a dated plan"
        case .presented: return "Presented"
        case .practicing: return "Practice work is open"
        case .reviewing: return "Work is in review, or closed without a mastery mark"
        case .mastered: return "Marked mastered"
        }
    }
}
