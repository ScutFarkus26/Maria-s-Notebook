import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// Delegates to:
// - MeetingPersistenceService: UserDefaults/SwiftData coordination
// - MeetingSummaryGenerator: AI summary generation
// - MeetingWorkSnapshotHelper: Work statistics computation

struct StudentMeetingsTab: View {
    let student: Student

    // MARK: - Environment & Data
    @Environment(\.modelContext) private var modelContext

    // Query all work models; we'll filter by studentID
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]

    // Query all lessons for lookup
    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var lessons: [Lesson]

    // Query all student lessons
    @Query(sort: [SortDescriptor(\StudentLesson.givenAt, order: .reverse)])
    private var allStudentLessons: [StudentLesson]

    // Query all meetings; we'll filter by studentID
    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var meetingItemsRaw: [StudentMeeting]

    // Query meeting templates to get active template for placeholders
    @Query(sort: [SortDescriptor(\MeetingTemplate.sortOrder)])
    private var meetingTemplates: [MeetingTemplate]

    // CloudKit compatibility: Convert UUID to String for comparison
    private var meetingItems: [StudentMeeting] {
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
        activeTemplate?.focusPrompt ?? "1–3 priorities…"
    }

    private var requestsPlaceholder: String {
        activeTemplate?.requestsPrompt ?? "Lessons the student wants…"
    }

    private var guideNotesPlaceholder: String {
        activeTemplate?.guideNotesPrompt ?? "Observations only…"
    }

    // MARK: - Local State for current meeting (persisted via UserDefaults per student)
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""

    @State private var expandedHistoryIDs: Set<UUID> = []
    @State private var meetingSummaries: [UUID: String] = [:]
    @State private var aiGeneratedSummaries: Set<UUID> = []
    @State private var generatingSummaries: Set<UUID> = []

    // Editing sheet state
    @State private var editingMeeting: StudentMeeting? = nil
    @State private var editDate: Date = Date()
    @State private var editCompleted: Bool = false
    @State private var editReflection: String = ""
    @State private var editFocus: String = ""
    @State private var editRequests: String = ""
    @State private var editGuideNotes: String = ""
    
    // Work detail sheet
    @State private var selectedWorkID: UUID? = nil

    // Work snapshot settings
    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = 14

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    // MARK: - Computed helpers for contracts and lessons (delegated to MeetingWorkSnapshotHelper)

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] { Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    private var workStats: (open: [WorkModel], overdue: [WorkModel], recentCompleted: [WorkModel]) {
        MeetingWorkSnapshotHelper.computeWorkStats(
            for: student.id,
            allWorkModels: allWorkModels,
            workOverdueDays: workOverdueDays
        )
    }

    private var openWorkModelsForStudent: [WorkModel] { workStats.open }
    private var overdueWorkModelsForStudent: [WorkModel] { workStats.overdue }
    private var recentCompletedWorkModelsForStudent: [WorkModel] { workStats.recentCompleted }

    private var openWorkCountText: String { openWorkModelsForStudent.isEmpty ? "—" : "\(openWorkModelsForStudent.count)" }
    private var overdueWorkCountText: String { overdueWorkModelsForStudent.isEmpty ? "—" : "\(overdueWorkModelsForStudent.count)" }
    private var recentlyCompletedWorkCountText: String { recentCompletedWorkModelsForStudent.isEmpty ? "—" : "\(recentCompletedWorkModelsForStudent.count)" }

    // MARK: - Lessons since last meeting (delegated to MeetingWorkSnapshotHelper)

    private var lastMeetingDate: Date? {
        meetingItems.first?.date
    }

    private var lessonsSinceLastMeetingForStudent: [StudentLesson] {
        MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: student.id,
            lastMeetingDate: lastMeetingDate,
            allStudentLessons: allStudentLessons
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
                            print("⚠️ [Edit meeting Save] Failed to save: \(error)")
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

    private var activeWorkSnapshotSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Work Snapshot")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        // Left column
                        VStack(alignment: .leading, spacing: 6) {
                            rowLine(label: "Open work", value: openWorkCountText)
                            if !openWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(openWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id
                                            }
                                    }
                                }
                            }
                            rowLine(label: "Overdue/stuck", value: overdueWorkCountText)
                            if !overdueWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(overdueWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id
                                            }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Right column
                        VStack(alignment: .leading, spacing: 6) {
                            rowLine(label: "Recently completed", value: recentlyCompletedWorkCountText)
                            if !recentCompletedWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(recentCompletedWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work, showCompletedDate: true)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id
                                            }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var lessonsSinceLastMeetingSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lessons Since Last Meeting")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                let lessonsSinceLastMeeting = lessonsSinceLastMeetingForStudent
                if lessonsSinceLastMeeting.isEmpty {
                    Text("No lessons since last meeting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lessonsSinceLastMeeting) { studentLesson in
                            lessonRowLine(studentLesson)
                        }
                    }
                }
            }
        }
    }
    
    private var historySection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting History")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if meetingItems.isEmpty {
                    Text("No prior meetings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(meetingItems) { item in
                            let isExpanded = expandedHistoryIDs.contains(item.id)
                            VStack(alignment: .leading, spacing: 0) {
                                // Header (always visible)
                                HStack(spacing: 8) {
                                    Text(Self.dateFormatter.string(from: item.date))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if item.completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    
                                    // Summary with AI indicator
                                    HStack(spacing: 4) {
                                        if let summary = meetingSummaries[item.id] {
                                            // Show sparkle only if AI actually generated it
                                            if aiGeneratedSummaries.contains(item.id) {
                                                Image(systemName: "sparkles")
                                                    .foregroundStyle(.purple)
                                                    .font(.caption2)
                                            }
                                            Text(summary)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        } else if generatingSummaries.contains(item.id) {
                                            ProgressView()
                                                .controlSize(.mini)
                                            Text("Summarizing...")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(summary(for: item))
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    
                                    Spacer()
                                    Menu {
                                        Button("Edit", systemImage: "square.and.pencil") { beginEdit(item) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        if isExpanded {
                                            expandedHistoryIDs.remove(item.id)
                                        } else {
                                            expandedHistoryIDs.insert(item.id)
                                        }
                                    }
                                }
                                
                                // Expanded content
                                if isExpanded {
                                    VStack(alignment: .leading, spacing: 6) {
                                        historyDetailLine(title: "Reflection", text: item.reflection)
                                        historyDetailLine(title: "Focus", text: item.focus)
                                        historyDetailLine(title: "Requests", text: item.requests)
                                        if !item.guideNotes.trimmed().isEmpty {
                                            historyDetailLine(title: "Guide notes", text: item.guideNotes)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .task {
                                // Generate summary when meeting appears
                                if meetingSummaries[item.id] == nil && !generatingSummaries.contains(item.id) {
                                    await generateSummary(for: item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }


    // MARK: - Helpers for Work display

    private func workRowLine(_ work: WorkModel, showCompletedDate: Bool = false) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: workDisplayTitle(work))
            if showCompletedDate, let date = work.completedAt {
                Text("•").foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workDisplayTitle(_ work: WorkModel) -> String {
        if let lid = UUID(uuidString: work.lessonID), let l = lessonsByID[lid] {
            return l.name
        }
        return "Lesson"
    }
    
    // MARK: - Helper for sheet binding
    
    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }
    
    private func lessonRowLine(_ studentLesson: StudentLesson) -> some View {
        HStack(spacing: 6) {
            BulletPointRow(text: lessonDisplayName(studentLesson), icon: "book.fill", iconSize: 8)
            if let givenAt = studentLesson.givenAt {
                Text("•").foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: givenAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if studentLesson.isPresented {
                Text("• Presented")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lessonDisplayName(_ studentLesson: StudentLesson) -> String {
        if let lesson = studentLesson.lesson {
            return lesson.name
        } else if let lessonID = UUID(uuidString: studentLesson.lessonID), let lesson = lessonsByID[lessonID] {
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

    private func beginEdit(_ item: StudentMeeting) {
        editDate = item.date
        editCompleted = item.completed
        editReflection = item.reflection
        editFocus = item.focus
        editRequests = item.requests
        editGuideNotes = item.guideNotes
        editingMeeting = item
    }

    private func delete(_ item: StudentMeeting) {
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [delete meeting] Failed to save: \(error)")
        }
    }

    // MARK: - UI Helpers

    private func rowLine(label: String, value: String) -> some View {
        LabelValueRow(label: label, value: value)
    }

    private func textArea(title: String, text: Binding<String>, placeholder: String) -> some View {
        PlaceholderTextArea(title: title, text: text, placeholder: placeholder)
    }

    private func historyDetailLine(title: String, text: String) -> some View {
        DetailLine(title: title, text: text)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        CardContainer(content: content)
    }

    // MARK: - Summary Generation (delegated to MeetingSummaryGenerator)

    private var isAIEnabled: Bool {
        MeetingSummaryGenerator.isAIEnabled
    }

    private func summary(for item: StudentMeeting) -> String {
        MeetingSummaryGenerator.generateFallbackSummary(for: item)
    }

    private func generateSummary(for item: StudentMeeting) async {
        generatingSummaries.insert(item.id)

        await MeetingSummaryGenerator.generateSummary(for: item) { [item] text, isAI in
            setSummary(text, for: item.id, isAIGenerated: isAI)
        }

        generatingSummaries.remove(item.id)
    }

    @MainActor
    private func setSummary(_ text: String, for meetingID: UUID, isAIGenerated: Bool = false) {
        meetingSummaries[meetingID] = text
        if isAIGenerated {
            aiGeneratedSummaries.insert(meetingID)
        } else {
            aiGeneratedSummaries.remove(meetingID)
        }
    }

    private static let dateFormatter: DateFormatter = {
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
