import SwiftUI
import SwiftData

struct StudentLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessonsAll: [StudentLesson]
    @Query private var workModels: [WorkModel]

    let studentLesson: StudentLesson
    var onDone: (() -> Void)? = nil

    @State private var scheduledFor: Date?
    @State private var givenAt: Date?
    @State private var notes: String
    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showingAddStudentSheet = false
    @State private var showingStudentPickerPopover = false
    @State private var studentSearchText: String = ""
    @State private var showDeleteAlert: Bool = false

    private enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    @State private var studentLevelFilter: LevelFilter = .all
    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        _scheduledFor = State(initialValue: studentLesson.scheduledFor)
        _givenAt = State(initialValue: studentLesson.givenAt)
        _notes = State(initialValue: studentLesson.notes)
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
        _selectedStudentIDs = State(initialValue: Set(studentLesson.studentIDs))
    }

    private var lessonObject: Lesson? {
        lessons.first(where: { $0.id == studentLesson.lessonID })
    }

    private var lessonName: String {
        lessonObject?.name ?? "Lesson"
    }

    private var subject: String {
        lessonObject?.subject ?? ""
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var nextLessonInGroup: Lesson? {
        guard let current = lessonObject else { return nil }
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        guard let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count else { return nil }
        return candidates[idx + 1]
    }

    private func planNextLessonInGroup() {
        guard let next = nextLessonInGroup else { return }
        let sameStudents = Set(selectedStudentIDs)
        let exists = studentLessonsAll.contains { sl in
            sl.lessonID == next.id && Set(sl.studentIDs) == sameStudents && sl.givenAt == nil
        }
        if !exists {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: next.id,
                studentIDs: Array(selectedStudentIDs),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
            newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
            newStudentLesson.syncSnapshotsFromRelationships()
            modelContext.insert(newStudentLesson)
            try? modelContext.save()
        }
        didPlanNext = true

        showPlannedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showPlannedBanner = false
        }
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    private var filteredStudentsForPicker: [Student] {
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched: [Student]
        if query.isEmpty {
            searched = studentsAll
        } else {
            searched = studentsAll.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }
        let leveled: [Student] = searched.filter { s in
            switch studentLevelFilter {
            case .all: return true
            case .lower: return s.level == .lower
            case .upper: return s.level == .upper
            }
        }
        return leveled.sorted {
            let lhs = ($0.firstName, $0.lastName)
            let rhs = ($1.firstName, $1.lastName)
            if lhs.0.caseInsensitiveCompare(rhs.0) == .orderedSame {
                return lhs.1.caseInsensitiveCompare(rhs.1) == .orderedAscending
            }
            return lhs.0.caseInsensitiveCompare(rhs.0) == .orderedAscending
        }
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            )
    }

    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d, h:mm a")
        return formatter
    }()
    
    private var scheduleStatusText: String {
        guard let date = scheduledFor else {
            return "Not Scheduled Yet"
        }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        let datePart = fmt.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Student Lesson")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    summarySection
                    scheduleSection
                    givenSection
                    nextLessonSection
                    flagsSection
                    followUpSection
                    notesSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 680, minHeight: 600)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button("Cancel") {
                        if let onDone {
                            onDone()
                        } else {
                            dismiss()
                        }
                    }

                    Button("Save") {
                        save()
                    }
                    .bold()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .overlay(alignment: .top) {
            if showPlannedBanner {
                plannedBanner
            }
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.titleLarge, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                if !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(subjectColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(subjectColor.opacity(0.15))
                        )
                }
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 8) {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedStudentsList, id: \.id) { student in
                            HStack(spacing: 6) {
                                Text(displayName(for: student))
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                Button {
                                    selectedStudentIDs.remove(student.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(subjectColor)
                                .accessibilityLabel("Remove \(displayName(for: student))")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(subjectColor)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(subjectColor.opacity(0.15))
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Label("Add/Remove Students", systemImage: "person.2.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
                    studentPickerPopover
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var studentPickerPopover: some View {
        VStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students", text: $studentSearchText)
                    .textFieldStyle(.plain)
                if !studentSearchText.isEmpty {
                    Button {
                        studentSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Picker("Level", selection: $studentLevelFilter) {
                Text("All").tag(LevelFilter.all)
                Text("Lower").tag(LevelFilter.lower)
                Text("Upper").tag(LevelFilter.upper)
            }
            .pickerStyle(.segmented)

            // Spacer between filters and list
            Divider().padding(.top, 2)

            // List of students with checkmarks
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudentsForPicker, id: \.id) { student in
                        Button {
                            if selectedStudentIDs.contains(student.id) {
                                selectedStudentIDs.remove(student.id)
                            } else {
                                selectedStudentIDs.insert(student.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedStudentIDs.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedStudentIDs.contains(student.id) ? Color.accentColor : Color.secondary)
                                Text(displayName(for: student))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Button {
                    showingAddStudentSheet = true
                } label: {
                    Label("New Student…", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    showingStudentPickerPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Scheduled For")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(scheduleStatusText)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(scheduledFor == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var givenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Presented", isOn: Binding(
                get: { givenAt != nil },
                set: { newValue in
                    if newValue {
                        givenAt = givenAt ?? Date()
                    } else {
                        givenAt = nil
                    }
                }
            ))

            if givenAt != nil {
                DatePicker("Date", selection: Binding(
                    get: { givenAt ?? Date() },
                    set: { givenAt = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextLessonSection: some View {
        Group {
            if givenAt != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Next Lesson in Group")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextLessonInGroup {
                        Text(next.name)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        Button {
                            planNextLessonInGroup()
                        } label: {
                            Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(didPlanNext || studentLessonsAll.contains { sl in
                            sl.lessonID == next.id && Set(sl.studentIDs) == Set(selectedStudentIDs) && sl.givenAt == nil
                        })
                    } else {
                        Text("No next lesson available")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Flags")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Needs Practice", isOn: $needsPractice)
            Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Follow Up Work")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("Follow Up Work", text: $followUpWork)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $notes)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plannedBanner: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.95))
            )
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }

    private func save() {
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork
        studentLesson.studentIDs = Array(selectedStudentIDs)

        studentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == studentLesson.lessonID })
        studentLesson.syncSnapshotsFromRelationships()
        
        // Auto-create a WorkModel for Needs Practice when flagged
        if needsPractice {
            let hasPracticeWork = workModels.contains { work in
                work.studentLessonID == studentLesson.id && work.workType == .practice
            }
            if !hasPracticeWork {
                let practiceWork = WorkModel(
                    id: UUID(),
                    studentIDs: Array(selectedStudentIDs),
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                modelContext.insert(practiceWork)
            }
        }

        // Auto-create a WorkModel for Follow Up Work when provided
        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let hasDuplicateFollowUp = workModels.contains { work in
                work.studentLessonID == studentLesson.id &&
                work.workType == .followUp &&
                work.notes.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedFollowUp) == .orderedSame
            }
            if !hasDuplicateFollowUp {
                let followUp = WorkModel(
                    id: UUID(),
                    studentIDs: Array(selectedStudentIDs),
                    workType: .followUp,
                    studentLessonID: studentLesson.id,
                    notes: trimmedFollowUp,
                    createdAt: Date()
                )
                modelContext.insert(followUp)
            }
        }

        do {
            try modelContext.save()
            if let onDone {
                onDone()
            } else {
                dismiss()
            }
        } catch {
            // Handle save error if needed
        }
    }

    private func delete() {
        // Delete synchronously first to avoid views reading a detached object
        modelContext.delete(studentLesson)
        do {
            try modelContext.save()
        } catch {
            // Handle delete error if needed
        }

        // Now dismiss after the @Query has updated
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}

#Preview {
    Text("StudentLessonDetailView preview requires real model data")
}
