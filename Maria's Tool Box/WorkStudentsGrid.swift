// WorkStudentsGrid.swift
// Shows an overview grid of students with their open work, matching the app's card/grid styling.

import SwiftUI

struct WorkStudentsGrid: View {
    let summaries: [StudentWorkSummary]
    let openWorksByStudentID: [UUID: [WorkModel]]
    let lookupService: WorkLookupService
    let onTapStudent: (Student) -> Void
    let onTapWork: (WorkModel) -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 24)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkTypeLegend()
                    .padding(.horizontal, 24)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(summaries) { summary in
                        StudentWorkCard(
                            summary: summary,
                            works: openWorksByStudentID[summary.id] ?? [],
                            lookupService: lookupService,
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
    let works: [WorkModel]
    let lookupService: WorkLookupService
    let onTapStudent: (Student) -> Void
    let onTapWork: (WorkModel) -> Void

    private var levelColor: Color {
        AppColors.color(forLevel: summary.student.level)
    }

    private func studentDisplayName(_ s: Student) -> String {
        StudentFormatter.displayName(for: s)
    }

    private func typeColor(_ type: WorkModel.WorkType) -> Color {
        switch type {
        case .practice: return .purple
        case .followUp: return .orange
        case .research: return .teal
        }
    }

    private func typeLabel(_ type: WorkModel.WorkType) -> String {
        switch type {
        case .practice: return "Practice"
        case .followUp: return "Follow-Up"
        case .research: return "Research"
        }
    }

    private func title(for work: WorkModel) -> String {
        if let slID = work.studentLessonID,
           let sl = lookupService.studentLessonsByID[slID],
           let lesson = lookupService.lessonsByID[sl.lessonID] {
            return lesson.name
        }
        let trimmed = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? typeLabel(work.workType) : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: student name + level pill + counts
            HStack(alignment: .top, spacing: 10) {
                Text(studentDisplayName(summary.student))
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .onTapGesture { onTapStudent(summary.student) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    CountBadge(count: summary.practiceOpen, color: .purple)
                    CountBadge(count: summary.followUpOpen, color: .orange)
                    CountBadge(count: summary.researchOpen, color: .teal)
                }
            }

            // Open works list (if any)
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(works, id: \.id) { work in
                        HStack(spacing: 8) {
                            Circle().fill(typeColor(work.workType)).frame(width: 6, height: 6)
                            Text(title(for: work))
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onTapWork(work) }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            } else {
                Text("No open work")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill({
                    #if os(macOS)
                    Color(NSColor.windowBackgroundColor)
                    #else
                    Color(uiColor: .secondarySystemBackground)
                    #endif
                }())
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct WorkTypeLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .purple, label: "Practice")
            legendItem(color: .orange, label: "Follow-Up")
            legendItem(color: .teal, label: "Research")
        }
        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

#Preview {
    Text("WorkStudentsGrid requires live data")
        .foregroundColor(.secondary)
        .italic()
}

