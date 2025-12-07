import SwiftUI

struct StudentWorkSummary: Identifiable {
    let id: UUID
    let student: Student
    let practiceOpen: Int
    let followUpOpen: Int
    let researchOpen: Int
    var totalOpen: Int { practiceOpen + followUpOpen + researchOpen }
}

struct WorkOverviewList: View {
    let summaries: [StudentWorkSummary]
    let openWorksByStudentID: [UUID: [WorkModel]]
    let lookupService: WorkLookupService
    let onTapStudent: (Student) -> Void
    let onTapWork: (WorkModel) -> Void

    init(
        summaries: [StudentWorkSummary],
        openWorksByStudentID: [UUID: [WorkModel]],
        lookupService: WorkLookupService,
        onTapStudent: @escaping (Student) -> Void,
        onTapWork: @escaping (WorkModel) -> Void
    ) {
        self.summaries = summaries
        self.openWorksByStudentID = openWorksByStudentID
        self.lookupService = lookupService
        self.onTapStudent = onTapStudent
        self.onTapWork = onTapWork
    }

    @State private var expanded: Set<UUID> = []

    var body: some View {
        List {
            WorkTypeLegendListRow()
            ForEach(summaries) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    let hasOpen = !(openWorksByStudentID[summary.id] ?? []).isEmpty

                    HStack(spacing: 12) {
                        InitialsCircleView(student: summary.student)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(studentDisplayName(summary.student))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            LevelPill(level: summary.student.level)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            CountPill(count: summary.practiceOpen, label: "Practice", color: .purple)
                            CountPill(count: summary.followUpOpen, label: "Follow-Up", color: .orange)
                            CountPill(count: summary.researchOpen, label: "Research", color: .teal)
                        }
                        TotalBadge(count: summary.totalOpen)
                        if hasOpen {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    if expanded.contains(summary.id) { expanded.remove(summary.id) } else { expanded.insert(summary.id) }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .rotationEffect(.degrees(expanded.contains(summary.id) ? 180 : 0))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(Circle().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(expanded.contains(summary.id) ? "Collapse" : "Expand")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapStudent(summary.student) }

                    if expanded.contains(summary.id), hasOpen {
                        let arr = openWorksByStudentID[summary.id] ?? []
                        MinimalOpenWorksList(
                            works: arr,
                            lookupService: lookupService,
                            onTapWork: onTapWork
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 8)
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    private func studentDisplayName(_ s: Student) -> String {
        return StudentFormatter.displayName(for: s)
    }
}

private struct MinimalOpenWorksList: View {
    let works: [WorkModel]
    let lookupService: WorkLookupService
    let onTapWork: (WorkModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(works, id: \.id) { work in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: work.workType))
                        .frame(width: 6, height: 6)
                    Text(title(for: work))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { onTapWork(work) }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func title(for work: WorkModel) -> String {
        if let slID = work.studentLessonID,
           let sl = lookupService.studentLessonsByID[slID],
           let lesson = lookupService.lessonsByID[sl.lessonID] {
            return lesson.name
        }
        return "Work"
    }

    private func color(for type: WorkModel.WorkType) -> Color {
        switch type {
        case .practice: return .purple
        case .followUp: return .orange
        case .research: return .teal
        }
    }

    private func typeLabel(for type: WorkModel.WorkType) -> String {
        switch type {
        case .practice: return "Practice"
        case .followUp: return "Follow-Up"
        case .research: return "Research"
        }
    }
}

private struct InitialsCircleView: View {
    let student: Student

    private var initials: String {
        let first = student.firstName.first.map(String.init) ?? ""
        let last = student.lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(color(for: student.level).opacity(0.9)))
    }

    private func color(for level: Student.Level) -> Color {
        switch level {
        case .lower: return .blue
        case .upper: return .pink
        }
    }
}

private struct LevelPill: View {
    let level: Student.Level

    var body: some View {
        Text(level.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        switch level {
        case .lower: return .blue
        case .upper: return .pink
        }
    }
}

private struct CountPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundColor(color)
                .background(Capsule().fill(color.opacity(0.12)))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

private struct TotalBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct WorkTypeLegendListRow: View {
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
    Text("WorkOverviewList requires live data")
        .foregroundColor(.secondary)
        .italic()
}
