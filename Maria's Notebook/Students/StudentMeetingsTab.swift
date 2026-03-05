import OSLog
import SwiftData
import SwiftUI

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// Delegates to:
// - MeetingPersistenceService: UserDefaults/SwiftData coordination
// - MeetingSummaryGenerator: AI summary generation
// - MeetingWorkSnapshotHelper: Work statistics computation

struct StudentMeetingsTab: View {
    static let logger = Logger.students

    let student: Student

    // MARK: - Environment & Data
    @Environment(\.modelContext) var modelContext

    // Query all work models; we'll filter by studentID
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    var allWorkModels: [WorkModel]

    // Query all lessons for lookup
    @Query(sort: [SortDescriptor(\Lesson.name)])
    var lessons: [Lesson]

    // Query all lesson assignments
    @Query(sort: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)])
    var allLessonAssignments: [LessonAssignment]

    // Query all meetings; we'll filter by studentID
    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var meetingItemsRaw: [StudentMeeting]

    // Query meeting templates to get active template for placeholders
    @Query(sort: [SortDescriptor(\MeetingTemplate.sortOrder)])
    var meetingTemplates: [MeetingTemplate]

    // CloudKit compatibility: Convert UUID to String for comparison
    var meetingItems: [StudentMeeting] {
        let studentIDString = student.id.uuidString
        return meetingItemsRaw.filter { $0.studentID == studentIDString }
    }

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: MeetingTemplate? {
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

    @State var expandedHistoryIDs: Set<UUID> = []
    @State var meetingSummaries: [UUID: String] = [:]
    @State var aiGeneratedSummaries: Set<UUID> = []
    @State var generatingSummaries: Set<UUID> = []

    // Editing sheet state
    @State var editingMeeting: StudentMeeting?
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
    var lessonsByID: [UUID: Lesson] { Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    private var workStats: (open: [WorkModel], overdue: [WorkModel], recentCompleted: [WorkModel]) {
        MeetingWorkSnapshotHelper.computeWorkStats(
            for: student.id,
            allWorkModels: allWorkModels,
            workOverdueDays: workOverdueDays
        )
    }

    var openWorkModelsForStudent: [WorkModel] { workStats.open }
    var overdueWorkModelsForStudent: [WorkModel] { workStats.overdue }
    var recentCompletedWorkModelsForStudent: [WorkModel] { workStats.recentCompleted }

    var openWorkCountText: String { openWorkModelsForStudent.isEmpty ? "\u{2014}" : "\(openWorkModelsForStudent.count)" }
    var overdueWorkCountText: String { overdueWorkModelsForStudent.isEmpty ? "\u{2014}" : "\(overdueWorkModelsForStudent.count)" }
    var recentlyCompletedWorkCountText: String { recentCompletedWorkModelsForStudent.isEmpty ? "\u{2014}" : "\(recentCompletedWorkModelsForStudent.count)" }

    // MARK: - Lessons since last meeting (delegated to MeetingWorkSnapshotHelper)

    private var lastMeetingDate: Date? {
        meetingItems.first?.date
    }

    var lessonsSinceLastMeetingForStudent: [LessonAssignment] {
        MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: student.id,
            lastMeetingDate: lastMeetingDate,
            allLessonAssignments: allLessonAssignments
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
                            try modelContext.save()
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

    func workRowLine(_ work: WorkModel, showCompletedDate: Bool = false) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: workDisplayTitle(work))
            if showCompletedDate, let date = work.completedAt {
                Text("\u{2022}").foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func workDisplayTitle(_ work: WorkModel) -> String {
        if let lid = UUID(uuidString: work.lessonID), let l = lessonsByID[lid] {
            return l.name
        }
        return "Lesson"
    }

    // MARK: - Helper for sheet binding

    struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    func lessonRowLine(_ la: LessonAssignment) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: lessonDisplayName(la), icon: "book.fill", iconSize: 8)
            if let presentedAt = la.presentedAt {
                Text("\u{2022}").foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: presentedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if la.isPresented {
                Text("\u{2022} Presented")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lessonDisplayName(_ la: LessonAssignment) -> String {
        if let lesson = la.lesson {
            return lesson.name
        } else if let lessonID = UUID(uuidString: la.lessonID), let lesson = lessonsByID[lessonID] {
            return lesson.name
        } else {
            return "Lesson"
        }
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
            guideNotesText: guideNotesText
        )
    }

    private func loadCurrentFromDefaults() {
        let data = MeetingPersistenceService.loadCurrent(studentID: student.id)
        isCompleted = data.isCompleted
        reflectionText = data.reflectionText
        focusText = data.focusText
        requestsText = data.requestsText
        guideNotesText = data.guideNotesText
    }

    private func saveCurrentToDefaults() {
        MeetingPersistenceService.saveCurrent(studentID: student.id, data: currentMeetingData)
    }

    private func clearCurrent() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        MeetingPersistenceService.clearCurrent(studentID: student.id)
    }

    private func migrateHistoryIfNeeded() {
        MeetingPersistenceService.migrateHistoryIfNeeded(
            studentID: student.id,
            existingMeetings: meetingItems,
            context: modelContext
        )
    }

    private func saveCurrentToHistory() {
        if MeetingPersistenceService.saveToHistory(
            studentID: student.id,
            data: currentMeetingData,
            context: modelContext
        ) {
            clearCurrent()
        }
    }

    func beginEdit(_ item: StudentMeeting) {
        editDate = item.date
        editCompleted = item.completed
        editReflection = item.reflection
        editFocus = item.focus
        editRequests = item.requests
        editGuideNotes = item.guideNotes
        editingMeeting = item
    }

    func delete(_ item: StudentMeeting) {
        modelContext.delete(item)
        do {
            try modelContext.save()
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

    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentMeetingsTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
