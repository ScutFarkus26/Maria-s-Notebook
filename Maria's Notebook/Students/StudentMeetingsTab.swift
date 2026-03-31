// swiftlint:disable file_length
import OSLog
import SwiftUI
import CoreData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// Delegates to:
// - MeetingPersistenceService: UserDefaults/SwiftData coordination
// - MeetingSummaryGenerator: AI summary generation
// - MeetingWorkSnapshotHelper: Work statistics computation

// swiftlint:disable:next type_body_length
struct StudentMeetingsTab: View {
    static let logger = Logger.students

    let student: CDStudent

    // MARK: - Environment & Data
    @Environment(\.managedObjectContext) var viewContext

    // Query all work models; we'll filter by studentID
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)])
    var allWorkModels: FetchedResults<CDWorkModel>

    // Query all lessons for lookup
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    var lessons: FetchedResults<CDLesson>

    // Query all lesson assignments
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)])
    var allLessonAssignments: FetchedResults<CDLessonAssignment>

    // Query all meetings; we'll filter by studentID
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)])
    private var meetingItemsRaw: FetchedResults<CDStudentMeeting>

    // Query meeting templates to get active template for placeholders
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDMeetingTemplate.sortOrder, ascending: true)])
    var meetingTemplates: FetchedResults<CDMeetingTemplate>

    // CloudKit compatibility: Convert UUID to String for comparison
    var meetingItems: [CDStudentMeeting] {
        let studentIDString = student.id?.uuidString ?? ""
        return meetingItemsRaw.filter { $0.studentID == studentIDString }
    }

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: CDMeetingTemplate? {
        meetingTemplates.first { $0.isActive }
    }

    // Template placeholder prompts (with fallbacks)
    private var reflectionPlaceholder: String {
        activeTemplate?.reflectionPrompt ?? "What went well? What was hard?"
    }

    private var focusPlaceholder: String {
        activeTemplate?.focusPrompt ?? "1-3 priorities..."
    }

    private var requestsPlaceholder: String {
        activeTemplate?.requestsPrompt ?? "Lessons the student wants..."
    }

    private var guideNotesPlaceholder: String {
        activeTemplate?.guideNotesPrompt ?? "Observations only..."
    }

    // MARK: - Local State for current meeting (persisted via UserDefaults per student)
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""
    @State private var nextMeetingDate: Date?

    @State var expandedHistoryIDs: Set<UUID> = []
    @State var meetingSummaries: [UUID: String] = [:]
    @State var aiGeneratedSummaries: Set<UUID> = []
    @State var generatingSummaries: Set<UUID> = []

    // Editing sheet state
    @State var editingMeeting: CDStudentMeeting?
    @State var editDate: Date = Date()
    @State var editCompleted: Bool = false
    @State var editReflection: String = ""
    @State var editFocus: String = ""
    @State var editRequests: String = ""
    @State var editGuideNotes: String = ""

    // Work detail sheet
    @State var selectedWorkID: UUID?

    // Work snapshot settings
    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = 14

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    // MARK: - Computed helpers for contracts and lessons (delegated to MeetingWorkSnapshotHelper)

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var lessonsByID: [UUID: CDLesson] { Dictionary(lessons.compactMap { l in l.id.map { ($0, l) } }, uniquingKeysWith: { first, _ in first }) }

    private var workStats: MeetingWorkSnapshotHelper.WorkStats {
        guard let studentID = student.id else { return MeetingWorkSnapshotHelper.WorkStats(open: [], overdue: [], recentCompleted: []) }
        return MeetingWorkSnapshotHelper.computeWorkStats(
            for: studentID,
            allWorkModels: Array(allWorkModels),
            workOverdueDays: workOverdueDays
        )
    }

    var openWorkModelsForStudent: [CDWorkModel] { workStats.open }
    var overdueWorkModelsForStudent: [CDWorkModel] { workStats.overdue }
    var recentCompletedWorkModelsForStudent: [CDWorkModel] { workStats.recentCompleted }

    var openWorkCountText: String {
        openWorkModelsForStudent.isEmpty ? "\u{2014}" : "\(openWorkModelsForStudent.count)"
    }
    var overdueWorkCountText: String {
        overdueWorkModelsForStudent.isEmpty ? "\u{2014}" : "\(overdueWorkModelsForStudent.count)"
    }
    var recentlyCompletedWorkCountText: String {
        recentCompletedWorkModelsForStudent.isEmpty
            ? "\u{2014}" : "\(recentCompletedWorkModelsForStudent.count)"
    }

    // MARK: - Lessons since last meeting (delegated to MeetingWorkSnapshotHelper)

    private var lastMeetingDate: Date? {
        meetingItems.first?.date
    }

    var lessonsSinceLastMeetingForStudent: [CDLessonAssignment] {
        guard let studentID = student.id else { return [] }
        return MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: studentID,
            lastMeetingDate: lastMeetingDate,
            allLessonAssignments: Array(allLessonAssignments)
        )
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            activeWorkSnapshotSection
            lessonsSinceLastMeetingSection
            historySection
            currentMeetingSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadCurrentFromDefaults()
            migrateHistoryIfNeeded()
        }
        .onChange(of: isCompleted) { _, _ in saveCurrentToDefaults() }
        .onChange(of: reflectionText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: focusText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: requestsText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: guideNotesText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: nextMeetingDate) { _, _ in saveCurrentToDefaults() }
        .sheet(item: $editingMeeting) { meeting in
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Meeting").font(.headline)
                DatePicker("Date", selection: $editDate, displayedComponents: .date)
                Toggle("Completed", isOn: $editCompleted)
                TextField("Reflection", text: $editReflection, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Focus", text: $editFocus, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Requests", text: $editRequests, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Guide notes", text: $editGuideNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Spacer()
                    Button("Cancel") { editingMeeting = nil }
                    Button("Save") {
                        meeting.date = editDate
                        meeting.completed = editCompleted
                        meeting.reflection = editReflection
                        meeting.focus = editFocus
                        meeting.requests = editRequests
                        meeting.guideNotes = editGuideNotes
                        do {
                            try viewContext.save()
                        } catch {
                            Self.logger.warning("Failed to save meeting edit: \(error)")
                        }
                        editingMeeting = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
#if os(macOS)
            .frame(minWidth: 420)
#endif
        }
        .sheet(item: Binding(
            get: { selectedWorkID.map { WorkIDWrapper(id: $0) } },
            set: { selectedWorkID = $0?.id }
        )) { wrapper in
            WorkDetailView(workID: wrapper.id) {
                selectedWorkID = nil
            }
        }
    }

    // MARK: - Sections

    private var currentMeetingSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                    Text("Weekly Meeting")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        saveCurrentToHistory()
                    } label: {
                        Label("Save to History", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCurrentEmpty)
                }

                HStack(alignment: .center) {
                    Label(todayString, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Completed", isOn: $isCompleted)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                textArea(title: "Student reflection", text: $reflectionText, placeholder: reflectionPlaceholder)
                textArea(title: "Focus for this week", text: $focusText, placeholder: focusPlaceholder)
                textArea(title: "Lesson requests", text: $requestsText, placeholder: requestsPlaceholder)
                textArea(title: "Guide notes (private)", text: $guideNotesText, placeholder: guideNotesPlaceholder)

                OptionalDatePicker(
                    toggleLabel: "Schedule Next Meeting",
                    dateLabel: "Next Meeting",
                    date: $nextMeetingDate,
                    displayedComponents: [.date]
                )

                HStack {
                    Spacer()
                    Button("Clear") {
                        clearCurrent()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers for Work display

    func workRowLine(_ work: CDWorkModel, showCompletedDate: Bool = false) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: workDisplayTitle(work))
            if showCompletedDate, let date = work.completedAt {
                Text("\u{2022}").foregroundStyle(.secondary)
                Text(DateFormatters.mediumDate.string(from: date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func workDisplayTitle(_ work: CDWorkModel) -> String {
        lessonsByID[uuidString: work.lessonID]?.name ?? "Lesson"
    }

    // MARK: - Helper for sheet binding

    struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    func lessonRowLine(_ la: CDLessonAssignment) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: lessonDisplayName(la), icon: "book.fill", iconSize: 8)
            if let presentedAt = la.presentedAt {
                Text("\u{2022}").foregroundStyle(.secondary)
                Text(DateFormatters.mediumDate.string(from: presentedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if la.isPresented {
                Text("\u{2022} Presented")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lessonDisplayName(_ la: CDLessonAssignment) -> String {
        la.lesson?.name ?? lessonsByID[uuidString: la.lessonID]?.name ?? "Lesson"
    }

    // MARK: - Persistence (delegated to MeetingPersistenceService)

    private var isCurrentEmpty: Bool {
        currentMeetingData.isEmpty
    }

    private var currentMeetingData: MeetingPersistenceService.CurrentMeetingData {
        MeetingPersistenceService.CurrentMeetingData(
            isCompleted: isCompleted,
            reflectionText: reflectionText,
            focusText: focusText,
            requestsText: requestsText,
            guideNotesText: guideNotesText,
            nextMeetingDate: nextMeetingDate
        )
    }

    private func loadCurrentFromDefaults() {
        guard let studentID = student.id else { return }
        let data = MeetingPersistenceService.loadCurrent(studentID: studentID)
        isCompleted = data.isCompleted
        reflectionText = data.reflectionText
        focusText = data.focusText
        requestsText = data.requestsText
        guideNotesText = data.guideNotesText
        nextMeetingDate = data.nextMeetingDate
    }

    private func saveCurrentToDefaults() {
        guard let studentID = student.id else { return }
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: currentMeetingData)
    }

    private func clearCurrent() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        nextMeetingDate = nil
        guard let studentID = student.id else { return }
        MeetingPersistenceService.clearCurrent(studentID: studentID)
    }

    private func migrateHistoryIfNeeded() {
        guard let studentID = student.id else { return }
        MeetingPersistenceService.migrateHistoryIfNeeded(
            studentID: studentID,
            existingMeetings: meetingItems,
            context: viewContext
        )
    }

    private func saveCurrentToHistory() {
        guard let studentID = student.id else { return }
        if MeetingPersistenceService.saveToHistory(
            studentID: studentID,
            data: currentMeetingData,
            context: viewContext
        ) {
            // Schedule next meeting if date was set
            if let date = nextMeetingDate {
                MeetingScheduler.scheduleMeeting(
                    studentID: studentID,
                    date: date,
                    context: viewContext
                )
            }
            clearCurrent()
        }
    }

    func beginEdit(_ item: CDStudentMeeting) {
        editDate = item.date ?? Date()
        editCompleted = item.completed
        editReflection = item.reflection
        editFocus = item.focus
        editRequests = item.requests
        editGuideNotes = item.guideNotes
        editingMeeting = item
    }

    func delete(_ item: CDStudentMeeting) {
        viewContext.delete(item)
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save after deleting meeting: \(error)")
        }
    }

    // MARK: - UI Helpers

    func rowLine(label: String, value: String) -> some View {
        LabelValueRow(label: label, value: value)
    }

    private func textArea(title: String, text: Binding<String>, placeholder: String) -> some View {
        PlaceholderTextArea(title: title, text: text, placeholder: placeholder)
    }

    func historyDetailLine(title: String, text: String) -> some View {
        DetailLine(title: title, text: text)
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        CardContainer(content: content)
    }

}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let student = Student(context: ctx)
    student.firstName = "Alan"
    student.lastName = "Turing"
    student.birthday = Date(timeIntervalSince1970: 0)
    student.level = .upper

    return StudentMeetingsTab(student: student)
        .previewEnvironment(using: stack)
        .padding()
}
