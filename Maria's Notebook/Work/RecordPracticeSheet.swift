// RecordPracticeSheet.swift
// Lesson-first practice recording sheet, launched from the pie menu.
// Flow: pick a lesson → see students with open practice work as chips → record observation.

import OSLog
import SwiftUI
import SwiftData

// swiftlint:disable:next type_body_length
struct RecordPracticeSheet: View {
    static let logger = Logger.work

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @Query private var allStudentsRaw: [Student]
    private var allStudents: [Student] { allStudentsRaw.filter { $0.isEnrolled } }
    @Query private var allLessons: [Lesson]
    @Query private var allWork: [WorkModel]

    // Lesson selection
    @State private var lessonPickerVM = LessonPickerViewModel()
    @State private var lessonSearchFocused = true

    // Student selection
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var manuallyAddedStudentIDs: Set<UUID> = []
    @State private var studentSearchText: String = ""

    // Session basics
    @State private var sessionDate: Date = Date()
    @State private var hasDuration: Bool = false
    @State private var durationMinutes: Int = 20

    // Quality metrics
    @State private var practiceQuality: Int?
    @State private var independenceLevel: Int?

    // Observable behaviors
    @State private var askedForHelp: Bool = false
    @State private var helpedPeer: Bool = false
    @State private var struggledWithConcept: Bool = false
    @State private var madeBreakthrough: Bool = false
    @State private var needsReteaching: Bool = false
    @State private var readyForCheckIn: Bool = false
    @State private var readyForAssessment: Bool = false

    // Next steps
    @State private var scheduleCheckIn: Bool = false
    @State private var checkInDate: Date = Date().addingTimeInterval(24 * 60 * 60)
    @State private var followUpActions: String = ""
    @State private var materialsUsed: String = ""

    // Notes
    @State private var sessionNotes: String = ""

    // MARK: - Computed

    private var selectedLesson: Lesson? {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return nil }
        return allLessons.first { $0.id == lessonID }
    }

    /// Open practice work items for the selected lesson
    private var openPracticeWork: [WorkModel] {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return [] }
        let lessonIDString = lessonID.uuidString
        return allWork.filter { work in
            work.lessonID == lessonIDString &&
            work.kindRaw == WorkKind.practiceLesson.rawValue &&
            work.isOpen
        }
    }

    /// Students who have open practice work for the selected lesson
    private var studentsWithOpenWork: [(student: Student, workItem: WorkModel)] {
        openPracticeWork.compactMap { work in
            guard let studentID = UUID(uuidString: work.studentID),
                  let student = allStudents.first(where: { $0.id == studentID }) else {
                return nil
            }
            return (student: student, workItem: work)
        }
        .sorted { $0.student.firstName < $1.student.firstName }
    }

    /// IDs of students who have open practice work (for chip display)
    private var practiceStudentIDs: Set<UUID> {
        Set(studentsWithOpenWork.map { $0.student.id })
    }

    /// All chip-visible students: those with open work + manually added
    private var chipStudents: [Student] {
        let ids = practiceStudentIDs.union(manuallyAddedStudentIDs)
        return allStudents
            .filter { ids.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }

    /// Students matching the search query (excluding those already shown as chips)
    private var searchResults: [Student] {
        guard !studentSearchText.isEmpty else { return [] }
        let chipIDs = Set(chipStudents.map { $0.id })
        let query = studentSearchText.lowercased()
        return allStudents
            .filter { !chipIDs.contains($0.id) }
            .filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query)
            }
            .sorted { $0.firstName < $1.firstName }
    }

    private var canSave: Bool {
        selectedLesson != nil && !selectedStudentIDs.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        lessonSection

                        if selectedLesson != nil {
                            Divider()
                            studentChipsSection

                            Divider()
                            dateSection

                            Divider()
                            durationSection

                            Divider()
                            qualityMetricsSection

                            Divider()
                            behaviorsSection

                            Divider()
                            notesSection

                            Divider()
                            nextStepsSection
                        }
                    }
                    .padding(24)
                }

                if selectedLesson != nil {
                    Divider()
                    bottomBar
                }
            }
            .navigationTitle("Record Practice")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                lessonPickerVM.configure(lessons: allLessons, students: allStudents)
            }
            .onChange(of: lessonPickerVM.selectedLessonID) { _, _ in
                // Pre-select all students with open practice work for this lesson
                selectedStudentIDs = practiceStudentIDs
                manuallyAddedStudentIDs = []
                studentSearchText = ""
            }
        }
    }

    // MARK: - Lesson Section

    private var lessonSection: some View {
        LessonPickerSection(
            viewModel: lessonPickerVM,
            resolvedLesson: selectedLesson,
            isFocused: $lessonSearchFocused
        )
    }

    // MARK: - Student Chips Section

    private var studentChipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Students")
                    .font(AppTheme.ScaledFont.calloutSemibold)

                if !selectedStudentIDs.isEmpty {
                    Text("\(selectedStudentIDs.count) selected")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if chipStudents.isEmpty {
                Text("No students have open practice work for this lesson.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                // Chip grid using FlowLayout wrapping
                FlowLayout(spacing: 8) {
                    ForEach(chipStudents) { student in
                        studentChip(for: student)
                    }
                }
            }

            // Search to add more students
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("Add student\u{2026}", text: $studentSearchText)
                        .font(AppTheme.ScaledFont.body)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )

                // Search results
                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { student in
                            Button {
                                manuallyAddedStudentIDs.insert(student.id)
                                selectedStudentIDs.insert(student.id)
                                studentSearchText = ""
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.accentColor)
                                    Text(StudentFormatter.displayName(for: student))
                                        .font(AppTheme.ScaledFont.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                    )
                }
            }
        }
    }

    private func studentChip(for student: Student) -> some View {
        let isSelected = selectedStudentIDs.contains(student.id)
        let hasOpenWork = practiceStudentIDs.contains(student.id)

        return Button {
            if isSelected {
                selectedStudentIDs.remove(student.id)
            } else {
                selectedStudentIDs.insert(student.id)
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.captionSemibold)
                if hasOpenWork {
                    Image(systemName: "book.fill")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Section

    private var dateSection: some View {
        DatePicker("Practice Date", selection: $sessionDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .font(AppTheme.ScaledFont.body)
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDuration) {
                Text("Track Duration")
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }

            if hasDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([10, 15, 20, 30], id: \.self) { minutes in
                            Button {
                                durationMinutes = minutes
                            } label: {
                                Text("\(minutes) min")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(durationMinutes == minutes ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(
                                                durationMinutes == minutes
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(0.1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Stepper("Custom: \(durationMinutes) min", value: $durationMinutes, in: 5...120, step: 5)
                        .font(AppTheme.ScaledFont.body)
                }
                .padding(.leading, 24)
            }
        }
    }

    // MARK: - Quality Metrics Section

    private var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality Metrics")
                .font(AppTheme.ScaledFont.calloutSemibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Practice Quality")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: practiceQuality, color: .blue) {
                            practiceQuality = level
                        }
                    }
                    Spacer()
                    if let quality = practiceQuality {
                        Text(qualityLabel(for: quality))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Independence Level")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: independenceLevel, color: .green) {
                            independenceLevel = level
                        }
                    }
                    Spacer()
                    if let independence = independenceLevel {
                        Text(independenceLabel(for: independence))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func qualityCircle(level: Int, selected: Int?, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.opacity((selected ?? 0) >= level ? 1.0 : 0.2))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
        }
    }

    // MARK: - Behaviors Section

    private var behaviorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observable Behaviors")
                .font(AppTheme.ScaledFont.calloutSemibold)

            VStack(spacing: 8) {
                behaviorToggle("Asked for help", isOn: $askedForHelp, icon: "hand.raised.fill", color: .orange)
                behaviorToggle("Helped a peer", isOn: $helpedPeer, icon: "hands.sparkles.fill", color: .green)
                behaviorToggle(
                    "Struggled with concept",
                    isOn: $struggledWithConcept,
                    icon: "exclamationmark.triangle.fill", color: .red
                )
                behaviorToggle(
                    "Made breakthrough",
                    isOn: $madeBreakthrough,
                    icon: "lightbulb.fill", color: .yellow
                )
                behaviorToggle(
                    "Needs reteaching",
                    isOn: $needsReteaching,
                    icon: "arrow.counterclockwise.circle.fill",
                    color: .purple
                )
                behaviorToggle(
                    "Ready for check-in",
                    isOn: $readyForCheckIn,
                    icon: "checkmark.circle.fill", color: .blue
                )
                behaviorToggle(
                    "Ready for assessment",
                    isOn: $readyForAssessment,
                    icon: "checkmark.seal.fill", color: .indigo
                )
            }
        }
    }

    private func behaviorToggle(_ label: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary)
                Text(label)
                    .font(AppTheme.ScaledFont.body)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Notes")
                .font(AppTheme.ScaledFont.calloutSemibold)

            TextEditor(text: $sessionNotes)
                .font(AppTheme.ScaledFont.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    // MARK: - Next Steps Section

    private var nextStepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Steps")
                .font(AppTheme.ScaledFont.calloutSemibold)

            Toggle(isOn: $scheduleCheckIn) {
                Text("Schedule Check-in")
                    .font(AppTheme.ScaledFont.body)
            }

            if scheduleCheckIn {
                DatePicker("Check-in Date", selection: $checkInDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(AppTheme.ScaledFont.body)
                    .padding(.leading, 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Follow-up Actions")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g., 'Reteach borrowing', 'Create scaffolded worksheet'",
                    text: $followUpActions, axis: .vertical
                )
                .font(AppTheme.ScaledFont.body)
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Materials Used")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField("e.g., 'Manipulatives', 'Worksheet pg 12'", text: $materialsUsed)
                    .font(AppTheme.ScaledFont.body)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                saveSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSave ? Color.accentColor : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(16)
    }

    // MARK: - Save

    @MainActor
    private func saveSession() {
        let repository = PracticeSessionRepository(modelContext: modelContext)

        // Collect matching work item IDs for selected students
        let workItemIDs: [UUID] = selectedStudentIDs.compactMap { studentID in
            openPracticeWork.first { $0.studentID == studentID.uuidString }?.id
        }

        let session = repository.create(
            date: sessionDate,
            duration: hasDuration ? TimeInterval(durationMinutes * 60) : nil,
            studentIDs: Array(selectedStudentIDs),
            workItemIDs: workItemIDs,
            sharedNotes: sessionNotes,
            location: nil
        )

        // Set quality metrics
        session.practiceQuality = practiceQuality
        session.independenceLevel = independenceLevel

        // Set behavior flags
        session.askedForHelp = askedForHelp
        session.helpedPeer = helpedPeer
        session.struggledWithConcept = struggledWithConcept
        session.madeBreakthrough = madeBreakthrough
        session.needsReteaching = needsReteaching
        session.readyForCheckIn = readyForCheckIn
        session.readyForAssessment = readyForAssessment

        // Set next steps
        if scheduleCheckIn {
            session.checkInScheduledFor = checkInDate
        }
        session.followUpActions = followUpActions
        session.materialsUsed = materialsUsed

        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save practice session: \(error)")
        }

        dismiss()
    }
}
