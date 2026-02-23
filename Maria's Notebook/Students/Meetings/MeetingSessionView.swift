import SwiftUI
import SwiftData

/// The main meeting session view showing student context and the meeting form side by side.
struct MeetingSessionView: View {
    let student: Student
    let allWorkModels: [WorkModel]
    let allStudentLessons: [StudentLesson]
    let lessons: [Lesson]
    let meetings: [StudentMeeting]
    let meetingTemplates: [MeetingTemplate]
    let workOverdueDays: Int
    var onComplete: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var lastMeetingDate: Date? {
        meetings.first?.date
    }

    // MARK: - Work Stats (delegated to helper)

    private var workStats: (open: [WorkModel], overdue: [WorkModel], recentCompleted: [WorkModel]) {
        MeetingWorkSnapshotHelper.computeWorkStats(
            for: student.id,
            allWorkModels: allWorkModels,
            workOverdueDays: workOverdueDays
        )
    }

    private var lessonsSinceLastMeeting: [StudentLesson] {
        MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: student.id,
            lastMeetingDate: lastMeetingDate,
            allStudentLessons: allStudentLessons
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > 900

            if isWide {
                // Side-by-side layout for wide screens
                HStack(spacing: 0) {
                    // Context pane (left)
                    MeetingContextPane(
                        student: student,
                        openWork: workStats.open,
                        overdueWork: workStats.overdue,
                        recentCompleted: workStats.recentCompleted,
                        lessonsSinceLastMeeting: lessonsSinceLastMeeting,
                        meetings: meetings,
                        lessonsByID: lessonsByID
                    )
                    .frame(width: min(geometry.size.width * 0.4, 400))
                    .background(Color.primary.opacity(0.02))

                    Divider()

                    // Meeting form (right)
                    MeetingFormPane(
                        student: student,
                        meetings: meetings,
                        meetingTemplates: meetingTemplates,
                        onComplete: onComplete
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Stacked layout for narrow screens
                ScrollView {
                    VStack(spacing: 24) {
                        // Context section (collapsible)
                        MeetingContextPane(
                            student: student,
                            openWork: workStats.open,
                            overdueWork: workStats.overdue,
                            recentCompleted: workStats.recentCompleted,
                            lessonsSinceLastMeeting: lessonsSinceLastMeeting,
                            meetings: meetings,
                            lessonsByID: lessonsByID,
                            isCompact: true
                        )

                        Divider()

                        // Meeting form
                        MeetingFormPane(
                            student: student,
                            meetings: meetings,
                            meetingTemplates: meetingTemplates,
                            onComplete: onComplete
                        )
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(StudentFormatter.displayName(for: student))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Context Pane

struct MeetingContextPane: View {
    let student: Student
    let openWork: [WorkModel]
    let overdueWork: [WorkModel]
    let recentCompleted: [WorkModel]
    let lessonsSinceLastMeeting: [StudentLesson]
    let meetings: [StudentMeeting]
    let lessonsByID: [UUID: Lesson]
    var isCompact: Bool = false

    @State private var selectedWorkID: UUID? = nil
    @State private var isContextCollapsed: Bool = false
    @State private var showAllOpenWork: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                if isCompact {
                    Button {
                        withAnimation { isContextCollapsed.toggle() }
                    } label: {
                        HStack {
                            Text("Student Context")
                                .font(.headline)
                            Spacer()
                            Image(systemName: isContextCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !isCompact || !isContextCollapsed {
                    // Work Snapshot
                    workSnapshotSection

                    // Lessons Since Last Meeting
                    lessonsSinceSection

                    // Meeting History Preview
                    meetingHistorySection
                }
            }
            .padding()
        }
        .sheet(item: Binding(
            get: { selectedWorkID.map { WorkIDWrapper(id: $0) } },
            set: { selectedWorkID = $0?.id }
        )) { wrapper in
            WorkDetailView(
                workID: wrapper.id,
                onDone: { selectedWorkID = nil },
                showRepresentButton: true
            )
        }
    }
    
    // MARK: - Helper for sheet binding
    
    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    // MARK: - Work Snapshot Section

    private var workSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Work Snapshot", icon: "tray.full")

            HStack(spacing: 16) {
                statBox(title: "Open", count: openWork.count, color: .blue)
                statBox(title: "Overdue", count: overdueWork.count, color: .orange)
                statBox(title: "Completed", count: recentCompleted.count, color: .green)
            }

            if !openWork.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Open Work")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if openWork.count > 5 {
                            Button {
                                withAnimation {
                                    showAllOpenWork.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(showAllOpenWork ? "Show Less" : "Show All (\(openWork.count))")
                                        .font(.caption)
                                    Image(systemName: showAllOpenWork ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(showAllOpenWork ? openWork : Array(openWork.prefix(5))) { work in
                        workRow(work)
                    }
                }
            }

            if !overdueWork.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overdue/Stuck")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)

                    ForEach(overdueWork.prefix(3)) { work in
                        workRow(work)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func statBox(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(count > 0 ? color : .secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func workRow(_ work: WorkModel) -> some View {
        Button {
            selectedWorkID = work.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)

                Text(workDisplayTitle(work))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func workDisplayTitle(_ work: WorkModel) -> String {
        if let lid = UUID(uuidString: work.lessonID), let lesson = lessonsByID[lid] {
            return lesson.name
        }
        return "Lesson"
    }

    // MARK: - Lessons Since Section

    private var lessonsSinceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Lessons Since Last Meeting", icon: "book")

            if lessonsSinceLastMeeting.isEmpty {
                Text("No lessons since last meeting")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(lessonsSinceLastMeeting.prefix(8)) { studentLesson in
                    lessonRow(studentLesson)
                }

                if lessonsSinceLastMeeting.count > 8 {
                    Text("+ \(lessonsSinceLastMeeting.count - 8) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func lessonRow(_ studentLesson: StudentLesson) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

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

            Spacer()

            if let givenAt = studentLesson.givenAt {
                Text(givenAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Meeting History Section

    private var meetingHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Meetings", icon: "clock")

            if meetings.isEmpty {
                Text("No prior meetings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(meetings.prefix(3)) { meeting in
                    meetingHistoryRow(meeting)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func meetingHistoryRow(_ meeting: StudentMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote.weight(.medium))

                if meeting.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()
            }

            if !meeting.focus.trimmed().isEmpty {
                Text(meeting.focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
    }
}

// MARK: - Meeting Form Pane

struct MeetingFormPane: View {
    let student: Student
    let meetings: [StudentMeeting]
    let meetingTemplates: [MeetingTemplate]
    var onComplete: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    // Form state
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""
    @State private var showingAddLessonSheet: Bool = false

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: MeetingTemplate? {
        meetingTemplates.first { $0.isActive }
    }

    private var reflectionPlaceholder: String {
        activeTemplate?.reflectionPrompt ?? "What went well? What was hard?"
    }

    private var focusPlaceholder: String {
        activeTemplate?.focusPrompt ?? "1–3 priorities for this week…"
    }

    private var requestsPlaceholder: String {
        activeTemplate?.requestsPrompt ?? "Lessons the student wants…"
    }

    private var guideNotesPlaceholder: String {
        activeTemplate?.guideNotesPrompt ?? "Observations only you can see…"
    }

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    private var isCurrentEmpty: Bool {
        reflectionText.trimmed().isEmpty &&
        focusText.trimmed().isEmpty &&
        requestsText.trimmed().isEmpty &&
        guideNotesText.trimmed().isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly Meeting")
                            .font(.title2.weight(.semibold))

                        Label(todayString, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Completed", isOn: $isCompleted)
                        .toggleStyle(.switch)
                        .labelsHidden()

                    Text("Completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form fields
                meetingField(title: "Student Reflection", text: $reflectionText, placeholder: reflectionPlaceholder)
                meetingField(title: "Focus for This Week", text: $focusText, placeholder: focusPlaceholder)
                meetingField(title: "Lesson Requests", text: $requestsText, placeholder: requestsPlaceholder)
                meetingField(title: "Guide Notes (private)", text: $guideNotesText, placeholder: guideNotesPlaceholder)

                // Action buttons
                HStack {
                    Button {
                        clearForm()
                    } label: {
                        Text("Clear")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        showingAddLessonSheet = true
                    } label: {
                        Label("Add Lesson to Inbox", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        saveAndContinue()
                    } label: {
                        Label("Save & Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrentEmpty)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddLessonSheet) {
            AddLessonToInboxSheet(student: student)
        }
        .onAppear {
            loadCurrentFromDefaults()
        }
        .onChange(of: student.id) { _, _ in
            // Save current before switching
            saveCurrentToDefaults()
            // Load new student's draft
            loadCurrentFromDefaults()
        }
        .onChange(of: reflectionText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: focusText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: requestsText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: guideNotesText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: isCompleted) { _, _ in saveCurrentToDefaults() }
    }

    // MARK: - Form Field

    private func meetingField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
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

                if text.wrappedValue.trimmed().isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Persistence

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

    private func clearForm() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        MeetingPersistenceService.clearCurrent(studentID: student.id)
    }

    private func saveAndContinue() {
        // Save to history
        if MeetingPersistenceService.saveToHistory(
            studentID: student.id,
            data: currentMeetingData,
            context: modelContext
        ) {
            clearForm()
            onComplete?()
        }
    }
}

// MARK: - Preview

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)

    return MeetingSessionView(
        student: student,
        allWorkModels: [],
        allStudentLessons: [],
        lessons: [],
        meetings: [],
        meetingTemplates: [],
        workOverdueDays: 14
    )
    .previewEnvironment(using: container)
}
