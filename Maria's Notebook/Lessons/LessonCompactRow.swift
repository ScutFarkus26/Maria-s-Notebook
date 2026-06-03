import SwiftUI

/// Compact, scannable lesson row used in the List browser and search results.
/// Shows name, area·sequence·section breadcrumb, and small status indicators.
struct LessonCompactRow: View {
    let lesson: CDLesson
    var statusCount: Int?
    var lastPresentedDate: Date?
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)

                if !breadcrumb.isEmpty {
                    Text(breadcrumb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let count = statusCount, count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                        Text("\(count)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }

                if let date = lastPresentedDate {
                    Text(relativeAgeString(for: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if lesson.pagesFileBookmark != nil || lesson.pagesFileRelativePath != nil {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                      ? Color.accentColor.opacity(UIConstants.OpacityConstants.moderate)
                      : Color.clear)
                .padding(.horizontal, 4)
        )
    }

    // MARK: - Helpers

    private var breadcrumb: String {
        [lesson.area.trimmed(), lesson.sequence.trimmed(), lesson.section.trimmed()]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func relativeAgeString(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86_400)
        if days < 1 { return "today" }
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        return "\(months)mo"
    }
}
