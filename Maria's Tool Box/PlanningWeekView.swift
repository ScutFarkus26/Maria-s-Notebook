import SwiftUI
import SwiftData


@MainActor struct PlanningWeekView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @State private var startDate: Date = Date()
    @State private var activeSheet: ActiveSheet? = nil

    private enum ActiveSheet: Identifiable {
        case studentLessonDetail(UUID)
        case quickActions(UUID)
        case giveLesson
        case addLesson
        case inbox

        var id: String {
            switch self {
            case .studentLessonDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLesson: return "giveLesson"
            case .addLesson: return "addLesson"
            case .inbox: return "inbox"
            }
        }
    }
    
    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .studentLessonDetail(let id):
            if let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonDetailView(studentLesson: sl) { activeSheet = nil }
            } else {
                EmptyView()
            }
        case .quickActions(let id):
            if let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonQuickActionsView(studentLesson: sl) { activeSheet = nil }
            } else {
                EmptyView()
            }
        case .giveLesson:
            GiveLessonSheet(
                lesson: nil,
                preselectedStudentIDs: [],
                startGiven: false,
                allStudents: students,
                allLessons: lessons
            )
            .largeSheetSizing()
        case .addLesson:
            AddLessonView(defaultSubject: nil, defaultGroup: nil)
                .largeSheetSizing()
        case .inbox:
            InboxViewContent(
                studentLessons: studentLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .studentLessonDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    try? modelContext.save()
                }
            )
            .largeSheetSizing()
        }
    }
    
    private var days: [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        while result.count < 7 {
            if !isNonSchoolDay(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }
    
    @MainActor private func planNextLesson(for sl: StudentLesson) {
        guard let currentLesson = lessons.first(where: { $0.id == sl.lessonID }) else { return }
        let currentSubject = currentLesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = currentLesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        guard let idx = candidates.firstIndex(where: { $0.id == currentLesson.id }), idx + 1 < candidates.count else { return }
        let next = candidates[idx + 1]

        let sameStudents = Set(sl.studentIDs)
        let exists = studentLessons.contains { existing in
            existing.lessonID == next.id && Set(existing.studentIDs) == sameStudents && existing.givenAt == nil
        }
        guard !exists else { return }

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: sl.studentIDs,
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = students.filter { sameStudents.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
        newStudentLesson.syncSnapshotsFromRelationships()
        modelContext.insert(newStudentLesson)
        try? modelContext.save()
    }
    
    private var orderedUnscheduledLessons: [StudentLesson] {
        InboxOrderStore.orderedUnscheduled(from: studentLessons, orderRaw: inboxOrderRaw)
    }
    
    private var sidebar: some View {
        PlanningSidebarView {
            InboxViewContent(
                studentLessons: studentLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .studentLessonDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    try? modelContext.save()
                }
            )
        }
    }
    
    var body: some View {
        contentView
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            .onAppear {
                DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: modelContext)
                startDate = computeInitialStartDate()
                syncInboxOrderWithCurrentBase()
            }
    }
    
    private var contentView: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                PlanningHeaderView(
                    weekRange: weekRangeString,
                    onPrevWeek: { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { moveStart(bySchoolDays: -7) } },
                    onNextWeek: { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { moveStart(bySchoolDays: 7) } },
                    onToday: { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { startDate = computeInitialStartDate() } },
                    onAddNew: { activeSheet = .giveLesson }
                )
                Divider()
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        WeekGrid(days: days, availableWidth: geometry.size.width - (UIConstants.contentHorizontalPadding * 2), availableHeight: geometry.size.height, onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) }, onQuickActions: { sl in activeSheet = .quickActions(sl.id) }, onPlanNext: { sl in planNextLesson(for: sl) })
                            .padding(.horizontal, UIConstants.contentHorizontalPadding)
                            .padding(.vertical, UIConstants.contentVerticalPadding)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: studentLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(Formatters.weekRange.string(from: first)) - \(Formatters.weekRange.string(from: last))"
    }

    private func isNonSchoolDay(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private func firstSchoolDay(onOrAfter date: Date) -> Date {
        var cursor = calendar.startOfDay(for: date)
        while isNonSchoolDay(cursor) {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cursor
    }

    private func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !isNonSchoolDay(cursor) { remaining -= 1 }
        }
        startDate = cursor
    }

    private func computeInitialStartDate() -> Date {
        let today = calendar.startOfDay(for: Date())
        let upcomingScheduled = studentLessons.compactMap { sl -> Date? in
            guard let s = sl.scheduledFor, !sl.isGiven else { return nil }
            let d = calendar.startOfDay(for: s)
            return d >= today ? d : nil
        }.sorted().first
        if let upcoming = upcomingScheduled, !isNonSchoolDay(upcoming) {
            return upcoming
        }
        return firstSchoolDay(onOrAfter: today)
    }

    @MainActor
    private func syncInboxOrderWithCurrentBase() {
        let base = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        let baseIDs = base.map { $0.id }
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = base
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
}

#Preview {
    PlanningWeekView()
        .frame(minWidth: 1000, minHeight: 600)
}

