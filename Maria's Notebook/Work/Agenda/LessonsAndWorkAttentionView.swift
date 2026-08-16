import CoreData
import SwiftUI

/// A single guide-facing queue for the active learning cycle. Presentation
/// follow-ups and actionable work remain separate rows because they represent
/// two different responsibilities: observe the child, and inspect the work.
@MainActor
struct LessonsAndWorkAttentionView: View {
    let openWork: [CDWorkModel]
    let scheduledCheckIns: [CDWorkCheckIn]
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    let searchText: String
    let focusedPresentationID: UUID?
    let focusedWorkID: UUID?
    let onOpenPresentation: (CDLessonAssignment) -> Void
    let onOpenWork: (CDWorkModel) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonPresentation.presentedAt, ascending: true)],
        predicate: NSPredicate(format: "followUpActionRaw != nil AND followUpResolvedAt == nil"),
        animation: .default
    ) private var followUpRows: FetchedResults<CDLessonPresentation>
    @FetchRequest(sortDescriptors: []) private var assignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var students: FetchedResults<CDStudent>

    private var groups: [FollowingPresentationGroup] {
        FollowingPresentationsService.groups(
            rows: Array(followUpRows),
            assignments: Array(assignments),
            lessons: Array(lessons),
            students: Array(students),
            searchText: searchText,
            context: viewContext,
            calendar: calendar
        )
    }

    private var visibleWork: [CDWorkModel] {
        openWork
            .filter(isVisibleAttentionWork)
            .sorted(by: sortWork)
    }

    private var dueWorkIDs: Set<UUID> {
        Set(scheduledCheckIns.compactMap { checkIn -> UUID? in
            guard let date = checkIn.date,
                  calendar.startOfDay(for: date) <= calendar.startOfDay(for: Date()) else {
                return nil
            }
            return UUID(uuidString: checkIn.workID)
        })
    }

    private func isVisibleAttentionWork(_ work: CDWorkModel) -> Bool {
        let query = searchText.trimmed().lowercased()
        let isDue = work.dueAt.map {
            calendar.startOfDay(for: $0) <= calendar.startOfDay(for: Date())
        } ?? false
        let needsGuide = work.status == .review
            || work.id.map(dueWorkIDs.contains) == true
            || isDue
            || isStale(work)
        guard needsGuide else { return false }
        return query.isEmpty || workSearchText(work).contains(query)
    }

    var body: some View {
        if groups.isEmpty && visibleWork.isEmpty {
            emptyState
        } else {
            attentionList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing Needs Your Attention",
            systemImage: "checkmark.circle",
            description: Text("Upcoming lessons and children’s active work remain available in the other views.")
        )
    }

    private var attentionList: some View {
        ScrollViewReader { proxy in
            List {
                presentationSection
                workSection
            }
            .listStyle(.inset)
            .task(id: focusedPresentationID) {
                guard let focusedPresentationID else { return }
                withAnimation { proxy.scrollTo(focusedPresentationID, anchor: .center) }
            }
            .task(id: focusedWorkID) {
                guard let focusedWorkID else { return }
                withAnimation { proxy.scrollTo(focusedWorkID, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var presentationSection: some View {
        if !groups.isEmpty {
            Section("Observe or Decide") {
                ForEach(groups) { group in
                    presentationRow(group)
                        .id(group.id)
                        .listRowBackground(rowBackground(group.id == focusedPresentationID))
                }
            }
        }
    }

    @ViewBuilder
    private var workSection: some View {
        if !visibleWork.isEmpty {
            Section("Check Work") {
                ForEach(visibleWork, id: \.objectID) { work in
                    workRow(work)
                        .id(work.id ?? UUID())
                        .listRowBackground(rowBackground(work.id == focusedWorkID))
                }
            }
        }
    }
}

private extension LessonsAndWorkAttentionView {
    func presentationRow(_ group: FollowingPresentationGroup) -> some View {
        Button {
            if let assignment = group.assignment { onOpenPresentation(assignment) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.lessonName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(group.childNames)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(group.actionSummary) • \(timingText(for: group))")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(group.assignment == nil)
        .accessibilityLabel(
            "Follow \(group.lessonName) for \(group.childNames). \(group.actionSummary)."
        )
    }

    func workRow(_ work: CDWorkModel) -> some View {
        WorkCard.list(
            work: work,
            title: displayTitle(for: work),
            subtitle: workSubtitle(for: work),
            badge: .status(workAttentionLabel(for: work)),
            onOpen: onOpenWork
        )
        .padding(.vertical, 3)
    }

    func timingText(for group: FollowingPresentationGroup) -> String {
        if let date = group.earliestReviewAt {
            return "Review \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        let days = group.schoolDaysSincePresentation
        return days == 0 ? "Presented today" : "\(days) school day\(days == 1 ? "" : "s") ago"
    }

    func displayTitle(for work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        guard title.isEmpty else { return title }
        let lessonName = lessonsByID[uuidString: work.lessonID]?.name.trimmed() ?? ""
        return lessonName.isEmpty ? "Open Work" : lessonName
    }

    func workSubtitle(for work: CDWorkModel) -> String {
        let student = studentsByID[uuidString: work.studentID]
            .map(StudentFormatter.displayName(for:)) ?? "Child"
        let kind = (work.kind ?? .practiceLesson).displayName
        if let dueAt = work.dueAt {
            return "\(student) • \(kind) • \(dueAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(student) • \(kind)"
    }

    func workAttentionLabel(for work: CDWorkModel) -> String {
        if let dueAt = work.dueAt,
           calendar.startOfDay(for: dueAt) <= calendar.startOfDay(for: Date()) {
            return calendar.isDateInToday(dueAt) ? "Check today" : "Overdue"
        }
        return work.status == .review ? "Review" : "Check"
    }

    func workSearchText(_ work: CDWorkModel) -> String {
        let student = studentsByID[uuidString: work.studentID]
            .map(StudentFormatter.displayName(for:)) ?? ""
        let lesson = lessonsByID[uuidString: work.lessonID]?.name ?? ""
        return "\(work.title) \(student) \(lesson) \((work.kind ?? .practiceLesson).displayName)"
            .lowercased()
    }

    func isStale(_ work: CDWorkModel) -> Bool {
        let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
        let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(
            for: work,
            checkIns: checkIns,
            notes: notes
        )
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: lastTouch,
            asOf: Date(),
            using: viewContext,
            calendar: calendar
        ) >= 10
    }

    func sortWork(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> Bool {
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return displayTitle(for: lhs).localizedCaseInsensitiveCompare(displayTitle(for: rhs)) == .orderedAscending
    }

    @ViewBuilder
    func rowBackground(_ isFocused: Bool) -> some View {
        if isFocused {
            Color.accentColor.opacity(0.12)
        } else {
            Color.clear
        }
    }
}
