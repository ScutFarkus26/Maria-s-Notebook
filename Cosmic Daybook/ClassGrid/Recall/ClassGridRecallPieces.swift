// ClassGridRecallPieces.swift
// The Recall view's parts: the retention tiles, a child's retention row, a
// child's heading over her due lessons, one due lesson, and the filter the
// area menu, search and children filter apply to the queue.

import SwiftUI

/// "Held this year 86%", "Checked 41", "To present again 3", "Faded over summer
/// 12%", and (Mac and iPad) the amber "Due for a check 12".
struct ClassGridRecallTiles: View {
    let summary: RecallRetentionStats.Summary?
    let fadePercent: Int?
    /// Nil leaves the Due tile out (the iPhone says it over the list).
    let dueCount: Int?
    let columns: Int

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 8
        ) {
            tile("Held this year", summary?.retentionPercent.map { "\($0)%" } ?? "—")
            tile("Checked", "\(summary?.observedCount ?? 0)")
            tile("To present again", "\(summary?.representCount ?? 0)")
            tile("Faded over summer", fadePercent.map { "\($0)%" } ?? "—")
            if let dueCount {
                tile("Due for a check", "\(dueCount)", isDue: true)
            }
        }
    }

    private func tile(_ label: String, _ value: String, isDue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(isDue ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isDue ? AnyShapeStyle(Color.orange.opacity(0.14)) : AnyShapeStyle(Color.primary.opacity(0.05)),
            in: .rect(cornerRadius: 10)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A child's name, a green bar for the share she held, and the percent.
struct ClassGridRecallChildRow: View {
    let row: RecallStudentRetention

    var body: some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                .frame(width: 54, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 54 * CGFloat(row.percent ?? 0) / 100, height: 5)
                }
            Text(row.percent.map { "\($0)%" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.percent.map { "Held \($0)%" } ?? "No checks yet")
    }
}

/// "Avigail G  3 due".
struct ClassGridRecallSectionHeader: View {
    let section: RecallStudentSection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.studentName)
                .font(.subheadline.weight(.bold))
            Text("\(section.entries.count) due")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChecklistGridMetrics.bandFill)
        .background(ChecklistGridMetrics.surface)
        .overlay(alignment: .bottom) { ChecklistGridMetrics.hairline.frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One due lesson: the mastered mark, its name, where it sits and why it's due,
/// and "covers N".
struct ClassGridRecallRow: View {
    let entry: RecallQueueEntry
    let isSelected: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            ChecklistMark(status: .mastered, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.frontierLessonName)
                    .font(.subheadline)
                    .lineLimit(2)
                Text("\(entry.area) · \(entry.sequence) · \(entry.dueReason.plainLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if entry.coversCount > 0 {
                Text("covers \(entry.coversCount)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.faint), in: Capsule())
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, showsChevron ? 14 : 20)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        // Selection is an ink outline, never accent blue: blue is the ladder's "started".
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension RecallDueReason {
    /// "summer recall", "due for a re-check".
    var plainLabel: String {
        switch self {
        case .startOfYearSweep: "summer recall"
        case .spacedDue: "due for a re-check"
        }
    }
}

/// The queue narrowed by the Class Grid's area, search and children filter.
enum RecallQueueFilter {
    static func sections(
        _ sections: [RecallStudentSection], area: String?, query: String, childIDs: Set<UUID>
    ) -> [RecallStudentSection] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let areaKey = area.map(ClassGridEngine.filingKey)
        return sections.compactMap { section in
            if !childIDs.isEmpty {
                guard let id = UUID(uuidString: section.id), childIDs.contains(id) else { return nil }
            }
            let entries = section.entries.filter { entry in
                if let areaKey, ClassGridEngine.filingKey(entry.area) != areaKey { return false }
                guard !tokens.isEmpty else { return true }
                let text = [section.studentName, entry.frontierLessonName, entry.area, entry.sequence]
                    .joined(separator: " ").lowercased()
                return tokens.allSatisfy(text.contains)
            }
            guard !entries.isEmpty else { return nil }
            return RecallStudentSection(id: section.id, studentName: section.studentName, entries: entries)
        }
    }
}
