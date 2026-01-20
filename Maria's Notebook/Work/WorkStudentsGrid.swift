import SwiftUI
import SwiftData
import Foundation // Fixes whitespacesAndNewlines error
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct StudentWorkSummary: Identifiable {
    let id: UUID
    let student: Student
    let practiceOpen: Int
    let followUpOpen: Int
    let researchOpen: Int
    var totalOpen: Int { practiceOpen + followUpOpen + researchOpen }
}

struct WorkStudentsGrid: View {
    let summaries: [StudentWorkSummary]
    // Keyed by UUID, values are WorkModels
    let openWorkByStudentID: [UUID: [WorkModel]]
    let lessonsByID: [UUID: Lesson]
    let onTapStudent: (Student) -> Void
    let onTapWork: (WorkModel) -> Void

    // Check size class to determine layout
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var columns: [GridItem] {
        // iPhone/Compact: Allow smaller cards (approx 160pt wide) to fit 2 columns
        // iPad/Regular: Keep the original 260pt minimum for wider cards
        let minWidth: CGFloat = sizeClass == .compact ? 155 : 260
        let spacing: CGFloat = sizeClass == .compact ? 16 : 24
        
        return [
            GridItem(.adaptive(minimum: minWidth, maximum: 320), spacing: spacing)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkTypeLegend()
                    .padding(.horizontal, 24)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(summaries) { summary in
                        StudentWorkCard(
                            summary: summary,
                            work: openWorkByStudentID[summary.id] ?? [],
                            lessonsByID: lessonsByID,
                            onTapStudent: onTapStudent,
                            onTapWork: onTapWork
                        )
                    }
                }
                .padding(24)
            }
        }
    }
}

private struct StudentWorkCard: View {
    let summary: StudentWorkSummary
    let work: [WorkModel]
    let lessonsByID: [UUID: Lesson]
    let onTapStudent: (Student) -> Void
    let onTapWork: (WorkModel) -> Void

    // Style flags
    var monochrome: Bool = false
    var dense: Bool = false
    var ultraDense: Bool = false
    var cornerRadius: CGFloat = 14
    var scale: CGFloat = 1.0

    private func studentDisplayName(_ s: Student) -> String {
        StudentFormatter.displayName(for: s)
    }

    private func kindColor(_ kind: WorkKind?) -> Color {
        if monochrome { return .primary }
        return kind?.color ?? .secondary
    }
    
    private var cardBackgroundColor: Color {
        if monochrome { return .white }
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    // Lookup via lessonsByID map
    private func title(for work: WorkModel) -> String {
        if !work.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return work.title
        }
        if let lid = UUID(uuidString: work.lessonID),
           let lesson = lessonsByID[lid] {
            return lesson.name
        }
        return "Untitled Work"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ultraDense ? 6 : (dense ? 8 : 12)) {
            HStack(alignment: .top, spacing: 10) {
                Text(studentDisplayName(summary.student))
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .onTapGesture { onTapStudent(summary.student) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    CountBadge(count: summary.practiceOpen, color: monochrome ? .primary : WorkKind.practiceLesson.color, monochrome: monochrome, dense: dense || ultraDense)
                    CountBadge(count: summary.followUpOpen, color: monochrome ? .primary : WorkKind.followUpAssignment.color, monochrome: monochrome, dense: dense || ultraDense)
                    CountBadge(count: summary.researchOpen, color: monochrome ? .primary : WorkKind.research.color, monochrome: monochrome, dense: dense || ultraDense)
                }
            }

            if !work.isEmpty {
                VStack(alignment: .leading, spacing: ultraDense ? 4 : (dense ? 6 : 8)) {
                    ForEach(work, id: \.id) { workItem in
                        HStack(spacing: ultraDense ? 4 : (dense ? 6 : 8)) {
                            Circle().fill(kindColor(workItem.kind)).frame(width: 6, height: 6)
                            Text(title(for: workItem))
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onTapWork(workItem) }
                    }
                }
                .padding(ultraDense ? 8 : (dense ? 10 : 12))
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            } else {
                Text("No open work").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(dense ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: dense ? 140 : 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color
    var monochrome: Bool = false
    var dense: Bool = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold))
            .foregroundStyle(monochrome ? .primary : color)
            .padding(.horizontal, dense ? 6 : 8)
            .padding(.vertical, dense ? 3 : 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct WorkTypeLegend: View {
    /// Work kinds to display in the legend (excludes report by default for this view)
    private let displayKinds: [WorkKind] = [.practiceLesson, .followUpAssignment, .research]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(displayKinds) { kind in
                legendItem(kind: kind)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func legendItem(kind: WorkKind) -> some View {
        HStack(spacing: 6) {
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Text(kind.shortLabel)
        }
    }
}
