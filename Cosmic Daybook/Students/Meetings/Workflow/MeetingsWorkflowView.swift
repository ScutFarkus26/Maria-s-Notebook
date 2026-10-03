import SwiftUI
import CoreData

/// A dedicated workflow view for conducting weekly student meetings: a queue
/// sorted by need beside the meeting itself.
///
/// The queue reads `MeetingQueueModel`'s per-child signals, rebuilt only when a
/// meeting, booking, work item, focus item or attendance mark changes; the
/// meeting fetches for its own child (`MeetingSessionView`).
struct MeetingsWorkflowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @TestStudentVisibility private var testStudents

    @State private var queueModel = MeetingQueueModel()
    @State private var selectedStudentID: UUID?
    @State private var searchText = ""
    @State private var selectedAgeRanges: Set<AgeRange> = []
    @State private var customOrder: [UUID] = []
    @State private var requeueStore = MeetingQueueRequeueStore()
    @State private var isAbsentExpanded = false
    @State private var isMetExpanded = false
    @State private var studentForMeetingDatePicker: CDStudent?

    @AppStorage(UserDefaultsKeys.meetingsWorkflowDaysSinceThreshold) private var cadenceDays: Int = 7
    @AppStorage(Self.orderKey) private var orderRaw: String = MeetingQueueOrder.need.rawValue
    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = WorkAgeDefaults.overdueDays

    private static let customOrderKey = "MeetingsWorkflow.customStudentOrder"
    private static let orderKey = "MeetingsWorkflow.queueOrder"

    // MARK: - Derived

    private var order: MeetingQueueOrder { MeetingQueueOrder(rawValue: orderRaw) ?? .need }

    /// Enrolled children (test students hidden when the setting is off), age filter applied.
    private var classStudents: [CDStudent] {
        let enrolled = testStudents.visible(dependencies.roster.enrolled)
        guard !selectedAgeRanges.isEmpty else { return enrolled }
        return enrolled.filter { AgeRange.matchesAny($0.birthday ?? Date(), in: selectedAgeRanges) }
    }

    private var rules: MeetingQueueRules {
        MeetingQueueRules(
            cadenceDays: cadenceDays,
            requeued: requeueStore.activeIDs { queueModel.signals[$0]?.lastMet },
            order: order,
            customOrder: customOrder
        )
    }

    private func arrangement(of students: [CDStudent]) -> MeetingQueueArrangement {
        // Read so the queue redraws at midnight: its cutoffs come from the clock.
        _ = queueModel.day
        return MeetingQueueArrangement.arrange(
            ids: students.compactMap(\.id), signals: queueModel.signals, rules: rules
        )
    }

    private func matchesSearch(_ student: CDStudent) -> Bool {
        let search = searchText.trimmed().lowercased()
        guard !search.isEmpty else { return true }
        return student.firstName.lowercased().contains(search) || student.lastName.lowercased().contains(search)
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: - Body

    /// Its own stack, so the iPad (which gives a sidebar tab no navigation
    /// bar) shows the title, the filter menu and search, and a phone can push
    /// a child's meeting.
    var body: some View {
        PageNavigationStack { page }
    }

    @ViewBuilder
    private var page: some View {
        let students = classStudents
        let byID = Dictionary(
            students.compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
        let queue = arrangement(of: students)
        let rows = { (ids: [UUID]) in ids.compactMap { byID[$0] }.filter(matchesSearch) }

        content(queue: queue, byID: byID, rows: rows)
            .navigationTitle("Meetings")
            .navigationSubtitle("\(queue.met.count) of \(queue.total) met · every \(cadenceDays) days")
            .inlineNavigationTitle()
            .searchable(text: $searchText, prompt: "Search")
            .toolbar { toolbarContent }
            .onAppear {
                loadCustomOrder()
                requeueStore = .load()
                refreshQueue()
            }
            .onReceiveWhenVisible(MeetingQueueModel.changes(), catchUpOnAppear: false) {
                queueModel.requestRefresh(context: viewContext, workOverdueDays: workOverdueDays)
            }
            // A meeting completed, a decision made, a booking changed: the
            // change flag is already set, so this rebuilds only if one moved.
            .onChange(of: selectedStudentID) { _, _ in refreshQueue() }
            .onReceive(NotificationCenter.default.publisher(for: .meetingDraftsDidChange)) { _ in
                queueModel.refreshDrafts()
            }
            .onChange(of: workOverdueDays) { _, _ in refreshQueue() }
            // Left open overnight (a Mac): yesterday's absences and bookings
            // give way to today's; the queue's day stamp makes this a rebuild.
            .onCalendarDayChange { refreshQueue() }
            .sheet(item: $studentForMeetingDatePicker) { student in
                MeetingDatePickerSheet(studentName: student.fullName) { date in
                    schedule(student, on: date)
                }
            }
    }

    @ViewBuilder
    private func content(
        queue: MeetingQueueArrangement,
        byID: [UUID: CDStudent],
        rows: ([UUID]) -> [CDStudent]
    ) -> some View {
        let sidebar = MeetingsQueueSidebar(
            upNext: rows(queue.upNext),
            absent: rows(queue.absent),
            met: rows(queue.met),
            metCount: queue.met.count,
            totalCount: queue.total,
            signals: queueModel.signals,
            draftIDs: queueModel.draftIDs,
            cadenceDays: cadenceDays,
            canReorder: order == .custom && searchText.trimmed().isEmpty,
            selectedStudentID: $selectedStudentID,
            isAbsentExpanded: $isAbsentExpanded,
            isMetExpanded: $isMetExpanded,
            onMove: { moveStudent(from: $0, to: $1, upNext: queue.upNext) },
            onRequeue: { requeueStudent($0, at: $1, upNext: queue.upNext) },
            onScheduleMeeting: schedule,
            onPickMeetingDate: { studentForMeetingDatePicker = $0 }
        )

        if isCompact {
            // A phone has no room for the queue beside the meeting: the
            // queue fills the screen and a child's meeting pushes over it.
            sidebar
                .navigationDestination(item: $selectedStudentID) { studentID in
                    if let student = byID[studentID] {
                        sessionView(for: student)
                    }
                }
        } else {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 280)
                Divider()
                Group {
                    if let id = selectedStudentID, let student = byID[id] {
                        sessionView(for: student)
                    } else {
                        let first = queue.upNext.first.flatMap { byID[$0] }
                        MeetingsEmptyState(
                            firstName: first?.shortName,
                            remaining: queue.upNext.count + queue.absent.count,
                            onStart: { selectedStudentID = first?.id }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sessionView(for student: CDStudent) -> some View {
        let id = student.id
        let upNext = arrangement(of: classStudents).upNext
        let index = id.flatMap { upNext.firstIndex(of: $0) }
        // Someone else is waiting: Complete moves on, and Skip is offered.
        let othersWaiting = upNext.contains { $0 != id }
        let hasPrevious = (index ?? 0) > 0
        let hasNext = index.map { $0 + 1 < upNext.count } ?? !upNext.isEmpty
        return MeetingSessionView(
            student: student,
            actions: MeetingSessionActions(
                completeLabel: othersWaiting ? "Complete & Next" : "Complete",
                onComplete: { advance(from: id) },
                onSkip: othersWaiting ? { advance(from: id) } : nil,
                onPrevious: hasPrevious ? { step(from: id, by: -1) } : nil,
                onNext: hasNext ? { step(from: id, by: 1) } : nil,
                scheduledDate: id.flatMap { queueModel.signals[$0]?.scheduled },
                onSchedule: { schedule(student, on: $0) }
            )
        )
        .id(student.objectID)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            MeetingsFilterMenu(
                cadenceDays: $cadenceDays,
                selectedAgeRanges: $selectedAgeRanges,
                orderRaw: $orderRaw,
                iconOnly: isCompact
            )
        }
        #if os(iOS)
        if order == .custom && isCompact {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        #endif
    }

    // MARK: - Refresh

    private func refreshQueue() {
        queueModel.refreshIfNeeded(context: viewContext, workOverdueDays: workOverdueDays)
    }

    // MARK: - Moving through the queue

    /// After Complete or Skip: the next child in Up Next after this one,
    /// wrapping to the top, or none when the queue is done.
    /// The next child is chosen from the queue as it stood, then the queue
    /// is refreshed so the child just met moves to Met.
    private func advance(from id: UUID?) {
        let upNext = arrangement(of: classStudents).upNext
        defer { refreshQueue() }
        guard let id, let index = upNext.firstIndex(of: id) else {
            selectedStudentID = upNext.first
            return
        }
        let others = upNext.filter { $0 != id }
        selectedStudentID = index + 1 < upNext.count ? upNext[index + 1] : others.first
    }

    private func step(from id: UUID?, by offset: Int) {
        let upNext = arrangement(of: classStudents).upNext
        guard let id, let index = upNext.firstIndex(of: id) else {
            selectedStudentID = upNext.first
            return
        }
        let target = index + offset
        guard upNext.indices.contains(target) else { return }
        selectedStudentID = upNext[target]
    }

    // MARK: - Scheduling

    private func schedule(_ student: CDStudent, on date: Date?) {
        guard let studentID = student.id else { return }
        if let date {
            MeetingScheduler.scheduleMeeting(studentID: studentID, date: date, context: viewContext)
        } else {
            MeetingScheduler.clearMeetings(studentID: studentID, context: viewContext)
        }
        refreshQueue()
    }

    // MARK: - Custom Order

    private func loadCustomOrder() {
        if let saved = UserDefaults.standard.array(forKey: Self.customOrderKey) as? [String] {
            customOrder = saved.compactMap { UUID(uuidString: $0) }
        }
    }

    private func saveCustomOrder() {
        UserDefaults.standard.set(customOrder.map(\.uuidString), forKey: Self.customOrderKey)
    }

    /// Rows hidden by a filter keep their place after the dragged ones.
    private func moveStudent(from source: IndexSet, to destination: Int, upNext: [UUID]) {
        var ids = upNext
        ids.move(fromOffsets: source, toOffset: destination)
        customOrder = ids + customOrder.filter { !ids.contains($0) }
        saveCustomOrder()
    }

    /// Puts a recently-met child back into Up Next. In custom order she lands
    /// at `position` (nil = the top); by need she sorts by her wait like anyone.
    private func requeueStudent(_ id: UUID, at position: Int?, upNext: [UUID]) {
        requeueStore.requeue(id) { queueModel.signals[$0]?.lastMet }
        requeueStore.save()
        guard order == .custom else { return }
        var ids = upNext.filter { $0 != id }
        ids.insert(id, at: min(position ?? 0, ids.count))
        customOrder = ids + customOrder.filter { !ids.contains($0) }
        saveCustomOrder()
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct MeetingsWorkflowViewPreview: View {
    var body: some View {
        MeetingsWorkflowView()
            .previewEnvironment()
    }
}

#Preview {
    MeetingsWorkflowViewPreview()
}
