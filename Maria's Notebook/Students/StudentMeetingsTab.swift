import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

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

    // CloudKit compatibility: Convert UUID to String for comparison
    private var meetingItems: [StudentMeeting] { 
        let studentIDString = student.id.uuidString
        return meetingItemsRaw.filter { $0.studentID == studentIDString } 
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

    // MARK: - Computed helpers for contracts and lessons

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }

    private var workModelsForStudent: [WorkModel] {
        let sid = student.id.uuidString
        return allWorkModels.filter { $0.studentID == sid }
    }

    private var openWorkModelsForStudent: [WorkModel] {
        workModelsForStudent.filter { $0.status != .complete }
    }

    private var overdueWorkModelsForStudent: [WorkModel] {
        let threshold = Calendar.current.date(byAdding: .day, value: -workOverdueDays, to: Date()) ?? Date.distantPast
        return workModelsForStudent.filter { $0.status != .complete && $0.createdAt < threshold }
    }

    private var recentCompletedWorkModelsForStudent: [WorkModel] {
        let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        return workModelsForStudent.filter { $0.status == .complete && ($0.completedAt ?? .distantPast) >= threshold }
    }

    private var openWorkCountText: String { openWorkModelsForStudent.isEmpty ? "—" : "\(openWorkModelsForStudent.count)" }
    private var overdueWorkCountText: String { overdueWorkModelsForStudent.isEmpty ? "—" : "\(overdueWorkModelsForStudent.count)" }
    private var recentlyCompletedWorkCountText: String { recentCompletedWorkModelsForStudent.isEmpty ? "—" : "\(recentCompletedWorkModelsForStudent.count)" }
    
    // MARK: - Lessons since last meeting
    
    private var lastMeetingDate: Date? {
        meetingItems.first?.date
    }
    
    private var lessonsSinceLastMeetingForStudent: [StudentLesson] {
        let studentIDString = student.id.uuidString
        let cutoffDate = lastMeetingDate ?? Date.distantPast
        
        return allStudentLessons.filter { studentLesson in
            // Check if this student is in the lesson
            guard studentLesson.studentIDs.contains(studentIDString) else { return false }
            
            // Check if lesson was given after the last meeting
            if let givenAt = studentLesson.givenAt {
                return givenAt > cutoffDate
            }
            // Also check if it was marked as presented after the last meeting
            if studentLesson.isPresented {
                return studentLesson.createdAt > cutoffDate
            }
            
            return false
        }
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
                        try? modelContext.save()
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
            WorkDetailContainerView(workID: wrapper.id) {
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

                textArea(title: "Student reflection", text: $reflectionText, placeholder: "What went well? What was hard?")
                textArea(title: "Focus for this week", text: $focusText, placeholder: "1–3 priorities…")
                textArea(title: "Lesson requests", text: $requestsText, placeholder: "Lessons the student wants…")
                textArea(title: "Guide notes (private)", text: $guideNotesText, placeholder: "Observations only…")

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
                                        if !item.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
            Text(workDisplayTitle(work))
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if showCompletedDate, let date = work.completedAt {
                Text("•").foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
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
            Image(systemName: "book.fill").font(.system(size: 8)).foregroundStyle(.secondary)
            if let lesson = studentLesson.lesson {
                Text(lesson.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            } else if let lessonID = UUID(uuidString: studentLesson.lessonID), let lesson = lessonsByID[lessonID] {
                Text(lesson.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            } else {
                Text("Lesson")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
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
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Persistence (UserDefaults for current, SwiftData for history)

    private var currentPrefix: String { "StudentMeetings.current." + student.id.uuidString }
    private var historyKey: String { "StudentMeetings.history." + student.id.uuidString }

    private var isCurrentEmpty: Bool {
        reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        focusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        requestsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        guideNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadCurrentFromDefaults() {
        let d = UserDefaults.standard
        isCompleted = d.bool(forKey: currentPrefix + ".completed")
        reflectionText = d.string(forKey: currentPrefix + ".reflection") ?? ""
        focusText = d.string(forKey: currentPrefix + ".focus") ?? ""
        requestsText = d.string(forKey: currentPrefix + ".requests") ?? ""
        guideNotesText = d.string(forKey: currentPrefix + ".guideNotes") ?? ""
    }

    private func saveCurrentToDefaults() {
        let d = UserDefaults.standard
        d.set(isCompleted, forKey: currentPrefix + ".completed")
        d.set(reflectionText, forKey: currentPrefix + ".reflection")
        d.set(focusText, forKey: currentPrefix + ".focus")
        d.set(requestsText, forKey: currentPrefix + ".requests")
        d.set(guideNotesText, forKey: currentPrefix + ".guideNotes")
    }

    private func clearCurrent() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        saveCurrentToDefaults()
    }

    private func migrateHistoryIfNeeded() {
        // If we already have SwiftData meetings for this student, skip migration
        if !meetingItems.isEmpty { return }
        let d = UserDefaults.standard
        guard let data = d.data(forKey: historyKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([LegacyMeetingEntry].self, from: data)
            var inserted = 0
            for entry in decoded {
                let m = StudentMeeting(
                    studentID: student.id,
                    date: entry.date,
                    completed: entry.completed,
                    reflection: entry.reflection,
                    focus: entry.focus,
                    requests: entry.requests,
                    guideNotes: entry.guideNotes
                )
                modelContext.insert(m)
                inserted += 1
            }
            if inserted > 0 { try? modelContext.save() }
            d.removeObject(forKey: historyKey)
        } catch {
            // If decoding fails, leave defaults as-is
        }
    }

    private func saveCurrentToHistory() {
        let trimmedReflection = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFocus = focusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequests = requestsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuide = guideNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedReflection.isEmpty && trimmedFocus.isEmpty && trimmedRequests.isEmpty && trimmedGuide.isEmpty) else { return }
        let entry = StudentMeeting(
            studentID: student.id,
            date: Date(),
            completed: isCompleted,
            reflection: trimmedReflection,
            focus: trimmedFocus,
            requests: trimmedRequests,
            guideNotes: trimmedGuide
        )
        modelContext.insert(entry)
        try? modelContext.save()
        clearCurrent()
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
        try? modelContext.save()
    }

    // MARK: - UI Helpers

    private func rowLine(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func textArea(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
                    )
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func historyDetailLine(title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Types & Formatters

    private struct LegacyMeetingEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let completed: Bool
        let reflection: String
        let focus: String
        let requests: String
        let guideNotes: String
    }

    private var isAIEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }
    
    private func summary(for item: StudentMeeting) -> String {
        // Fallback summary when AI hasn't generated one yet
        return generateFallbackSummary(for: item)
    }
    
    private func generateFallbackSummary(for item: StudentMeeting) -> String {
        // For single-line display, prefer the most important field first
        let focusTrim = item.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focusTrim.isEmpty { 
            return focusTrim.count > 60 ? String(focusTrim.prefix(57)) + "..." : focusTrim
        }
        let reflTrim = item.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reflTrim.isEmpty { 
            return reflTrim.count > 60 ? String(reflTrim.prefix(57)) + "..." : reflTrim
        }
        let reqTrim = item.requests.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reqTrim.isEmpty { 
            return reqTrim.count > 60 ? String(reqTrim.prefix(57)) + "..." : reqTrim
        }
        let guideTrim = item.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !guideTrim.isEmpty { 
            return guideTrim.count > 60 ? String(guideTrim.prefix(57)) + "..." : guideTrim
        }
        return "Meeting"
    }
    
    private func generateSummary(for item: StudentMeeting) async {
        let manualSummary = generateFallbackSummary(for: item)
        
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            setSummary(manualSummary, for: item.id, isAIGenerated: false)
            return
        }
        
        // Don't burn AI tokens if the content is very short
        let totalLength = item.reflection.count + item.guideNotes.count + item.focus.count + item.requests.count
        guard totalLength > 30 else {
            setSummary(manualSummary, for: item.id, isAIGenerated: false)
            return
        }
        
        generatingSummaries.insert(item.id)
        
        let context = """
        Student Reflection: \(item.reflection)
        Focus: \(item.focus)
        Requests: \(item.requests)
        Guide Notes: \(item.guideNotes)
        """
        
        let instructions = "You are a Montessori guide assistant. Summarize this student meeting outcomes and sentiment in 2 sentences."
        let session = LanguageModelSession(instructions: instructions)
        
        do {
            let stream = session.streamResponse(
                to: "Summarize this meeting:\n\(context)",
                generating: MeetingSummary.self
            )
            
            var aiGenerated = false
            for try await partial in stream {
                if let overview = partial.content.overview, !overview.isEmpty {
                    setSummary(overview, for: item.id, isAIGenerated: true)
                    aiGenerated = true
                }
            }
            
            if !aiGenerated {
                // If stream completed but no summary was generated, use fallback
                setSummary(manualSummary, for: item.id, isAIGenerated: false)
            }
        } catch {
            #if DEBUG
            print("AI Summary failed: \(error)")
            #endif
            setSummary(manualSummary, for: item.id, isAIGenerated: false)
        }
        
        generatingSummaries.remove(item.id)
        
        #else
        // Fallback: AI disabled
        setSummary(manualSummary, for: item.id, isAIGenerated: false)
        #endif
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
