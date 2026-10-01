import SwiftUI
import CoreData

/// One child's meeting: a header band, what happened since the last meeting
/// beside the form on a wide screen (stacked under a strip of chips on a
/// phone), and a pinned footer that keeps Complete in reach.
///
/// Everything is fetched for this child alone. Give the view an `.id` per
/// child so its draft starts fresh when the selection changes.
struct MeetingSessionView: View {
    let student: CDStudent
    var actions = MeetingSessionActions()

    @FetchRequest private var meetings: FetchedResults<CDStudentMeeting>

    init(student: CDStudent, actions: MeetingSessionActions = MeetingSessionActions()) {
        self.student = student
        self.actions = actions
        _meetings = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)],
            predicate: NSPredicate(format: "studentID == %@", student.id?.uuidString ?? "")
        )
    }

    var body: some View {
        let lastMeetingDate = meetings.first?.date
        MeetingSessionContent(
            student: student,
            meetings: Array(meetings),
            lastMeetingDate: lastMeetingDate,
            lessonsCutoff: SchoolYearCounters.countFrom(lastMeetingDate ?? .distantPast),
            actions: actions
        )
    }
}

/// What the session can ask of whoever shows it. A nil action hides its control.
struct MeetingSessionActions {
    var completeLabel = "Complete Meeting"
    var onComplete: (() -> Void)?
    var onSkip: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    /// The child's booked meeting, for the ⋯ menu.
    var scheduledDate: Date?
    /// Books (or, with nil, clears) the child's next meeting.
    var onSchedule: ((Date?) -> Void)?
}

// MARK: - Content

private struct MeetingSessionContent: View {
    let student: CDStudent
    let meetings: [CDStudentMeeting]
    let lastMeetingDate: Date?
    let actions: MeetingSessionActions

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @FetchRequest private var work: FetchedResults<CDWorkModel>
    @FetchRequest private var recentAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDMeetingTemplate.sortOrder, ascending: true)])
    private var templates: FetchedResults<CDMeetingTemplate>

    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = WorkAgeDefaults.overdueDays

    @State private var draft: MeetingDraftModel
    @State private var width: CGFloat = 1000
    @State private var compactSheet: MeetingCompactSheet.Kind?
    @State private var isConfirmingClear = false
    @State private var isPickingScheduleDate = false

    init(
        student: CDStudent,
        meetings: [CDStudentMeeting],
        lastMeetingDate: Date?,
        lessonsCutoff: Date,
        actions: MeetingSessionActions
    ) {
        self.student = student
        self.meetings = meetings
        self.lastMeetingDate = lastMeetingDate
        self.actions = actions
        let studentID = student.id ?? UUID()
        _draft = State(initialValue: MeetingDraftModel(studentID: studentID))
        _work = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: true)],
            predicate: NSPredicate(format: "studentID == %@", studentID.uuidString)
        )
        _recentAssignments = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)],
            predicate: MeetingWorkSnapshotHelper.lessonsSincePredicate(cutoff: lessonsCutoff)
        )
    }

    private var isWide: Bool {
        #if os(iOS)
        if horizontalSizeClass == .compact { return false }
        #endif
        return width >= 760
    }

    var body: some View {
        let sessionWork = MeetingWorkSnapshotHelper.sessionWork(
            Array(work), workOverdueDays: workOverdueDays, reviewed: draft.reviewedWorkIDs
        )
        let studentIDString = student.id?.uuidString ?? ""
        let lessons = recentAssignments.filter { $0.studentIDs.contains(studentIDString) }
        let summary = MeetingSessionSummary(
            stuck: sessionWork.stuck.count,
            focusCarried: draft.activeFocusItems.count,
            lessonsSince: lessons.count
        )

        Group {
            if isWide {
                wideLayout(sessionWork: sessionWork, lessons: lessons, summary: summary)
            } else {
                compactLayout(sessionWork: sessionWork, lessons: lessons, summary: summary)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { draft.load(context: viewContext) }
        .onDisappear { draft.flush() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { draft.flush() }
        }
        .confirmationDialog("Clear this meeting?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Meeting", role: .destructive) { draft.clear() }
        } message: {
            Text("Everything written for \(student.firstName)'s meeting so far will be erased.")
        }
        .sheet(isPresented: $isPickingScheduleDate) {
            MeetingDatePickerSheet(studentName: student.fullName) { date in
                actions.onSchedule?(date)
            }
        }
    }

    // MARK: - Wide

    private func wideLayout(
        sessionWork: MeetingWorkSnapshotHelper.SessionWork,
        lessons: [CDLessonAssignment],
        summary: MeetingSessionSummary
    ) -> some View {
        VStack(spacing: 0) {
            MeetingSessionHeader(
                student: student,
                lastMeetingDate: lastMeetingDate,
                summary: summary,
                actions: actions,
                moreMenu: { moreMenuItems }
            )
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    contextPane(sessionWork: sessionWork, lessons: lessons)
                        .padding(16)
                }
                .frame(width: min(max(width * 0.36, 300), 380))
                .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))

                Divider()

                VStack(spacing: 0) {
                    ScrollView {
                        MeetingFormPane(draft: draft, template: activeTemplate)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                            .frame(maxWidth: 720, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    footer(decided: decidedCount(sessionWork.stuck), of: sessionWork.stuck.count)
                }
            }
        }
    }

    // MARK: - Compact

    private func compactLayout(
        sessionWork: MeetingWorkSnapshotHelper.SessionWork,
        lessons: [CDLessonAssignment],
        summary: MeetingSessionSummary
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MeetingSummaryChips(summary: summary, isButtons: true) { chip in
                        switch chip {
                        case .stuck: compactSheet = .decisions
                        case .focus: adaptiveWithAnimation { proxy.scrollTo("focus", anchor: .top) }
                        case .lessons: compactSheet = .lessons
                        case .meetings: compactSheet = .meetings
                        }
                    }
                    if !sessionWork.stuck.isEmpty {
                        CompactDecisionPager(stuck: sessionWork.stuck, draft: draft, workTitle: names.workTitle)
                    }
                    MeetingFormPane(draft: draft, template: activeTemplate)
                        .id("focus")
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                footer(decided: decidedCount(sessionWork.stuck), of: sessionWork.stuck.count)
                    .background(.bar)
            }
        }
        .navigationTitle(student.fullName)
        .navigationSubtitle(MeetingSessionText.lastMetText(lastMeetingDate))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    moreMenuItems
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(item: $compactSheet) { sheet in
            MeetingCompactSheet(
                sheet: sheet,
                sessionWork: sessionWork,
                lessons: lessons,
                meetings: meetings,
                lastMeetingDate: lastMeetingDate,
                draft: draft,
                names: names,
                onDone: { compactSheet = nil }
            )
        }
    }

    // MARK: - Pieces

    private func contextPane(
        sessionWork: MeetingWorkSnapshotHelper.SessionWork,
        lessons: [CDLessonAssignment]
    ) -> some View {
        MeetingContextPane(
            stuckWork: sessionWork.stuck,
            openWork: sessionWork.open,
            lessonsSince: lessons,
            meetings: meetings,
            lastMeetingDate: lastMeetingDate,
            draft: draft,
            workTitle: names.workTitle,
            lessonName: names.lessonName,
            lessonArea: { names.lesson(for: $0)?.area }
        )
    }

    private func footer(decided: Int, of total: Int) -> some View {
        MeetingSessionFooter(
            isEmpty: draft.isEmpty,
            savedAt: draft.savedAt,
            decided: decided,
            decisionsTotal: total,
            completeLabel: actions.completeLabel,
            onSkip: actions.onSkip.map { skip in { draft.flush(); skip() } },
            onComplete: complete
        )
    }

    private var moreMenuItems: some View {
        MeetingMoreMenuItems(
            scheduledDate: actions.scheduledDate,
            onSchedule: actions.onSchedule,
            canClear: !draft.isEmpty,
            onPickDay: { isPickingScheduleDate = true },
            onClear: { isConfirmingClear = true }
        )
    }

    private func complete() {
        let completed = draft.complete(context: viewContext, saveCoordinator: saveCoordinator) { id in
            dependencies.lessonCatalog.lesson(id: id)?.name
        }
        if completed { actions.onComplete?() }
    }

    private var activeTemplate: CDMeetingTemplate? {
        templates.first { $0.isActive }
    }

    private func decidedCount(_ stuck: [CDWorkModel]) -> Int {
        stuck.filter { $0.id.map(draft.reviewedWorkIDs.contains) ?? false }.count
    }

    private var names: MeetingCatalogNames { MeetingCatalogNames(catalog: dependencies.lessonCatalog) }
}
