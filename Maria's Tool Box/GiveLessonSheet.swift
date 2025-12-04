import SwiftUI
import SwiftData
import Foundation
import Combine

struct GiveLessonSheet: View {
    let initialLesson: Lesson?
    let allStudents: [Student]
    let allLessons: [Lesson]
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var viewModel: GiveLessonViewModel

    @Query private var queriedStudents: [Student]
    @Query private var queriedLessons: [Lesson]
    
    init(lesson: Lesson? = nil, preselectedStudentIDs: [UUID] = [], startGiven: Bool = false, allStudents: [Student] = [], allLessons: [Lesson] = [], onDone: (() -> Void)? = nil) {
        self.initialLesson = lesson
        self.allStudents = allStudents
        self.allLessons = allLessons
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: GiveLessonViewModel(
            selectedStudentIDs: Set(preselectedStudentIDs),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            selectedLessonID: lesson?.id,
            mode: startGiven ? .given : .plan
        ))
    }
    

    @State private var sortedLessons: [Lesson] = []
    @State private var sortedStudents: [Student] = []
    
    @State private var lessonSearchText: String = ""
    @State private var showFollowUpField: Bool = false
    
    @State private var studentLevelFilter: LevelFilter = .all

    private enum FocusField: Hashable { case lesson, notes, followUp }
    @FocusState private var focusedField: FocusField?

    private var selectedLessonIDBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedLessonID },
            set: { viewModel.selectedLessonID = $0 }
        )
    }

    private var lessonFocusBinding: Binding<Bool> {
        Binding(
            get: { focusedField == .lesson },
            set: { focusedField = $0 ? .lesson : nil }
        )
    }
    
    private var lessonsSource: [Lesson] { allLessons.isEmpty ? queriedLessons : allLessons }
    private var studentsSource: [Student] { allStudents.isEmpty ? queriedStudents : allStudents }
    
    private var resolvedLesson: Lesson? {
        if let id = viewModel.selectedLessonID {
            return lessonsSource.first(where: { $0.id == id })
        } else {
            return initialLesson
        }
    }
    
    enum Mode: Hashable { case plan, given }
    
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var studentSearchText: String = ""
    
    @State private var saveAlert: (title: String, message: String)? = nil

    enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    private var subjectColor: Color {
        if let s = resolvedLesson?.subject, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppColors.color(forSubject: s)
        }
        return .accentColor
    }
    
    private var sortedLessonsForPicker: [Lesson] { sortedLessons }
    
    private var filteredLessonsForSearch: [Lesson] {
        let query = lessonSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return sortedLessonsForPicker }
        return sortedLessonsForPicker.filter { l in
            let name = l.name.lowercased()
            let subject = l.subject.lowercased()
            let group = l.group.lowercased()
            return name.contains(query) || subject.contains(query) || group.contains(query)
        }
    }

    private var selectedStudentsList: [Student] {
        sortedStudents.filter { viewModel.selectedStudentIDs.contains($0.id) }
    }

    private var filteredStudentsForPicker: [Student] {
        var filtered = sortedStudents

        switch studentLevelFilter {
        case .lower:
            filtered = filtered.filter { $0.level == .lower }
        case .upper:
            filtered = filtered.filter { $0.level == .upper }
        case .all:
            break
        }

        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }

        return filtered
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
    
    private func lessonDisplayTitle(for lesson: Lesson) -> String {
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)

        var suffix = ""
        if !subject.isEmpty && !group.isEmpty {
            suffix = " • \(subject) • \(group)"
        } else if !subject.isEmpty {
            suffix = " • \(subject)"
        } else if !group.isEmpty {
            suffix = " • \(group)"
        }

        return lesson.name + suffix
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if resolvedLesson != nil {
                    Circle()
                        .fill(subjectColor)
                        .frame(width: 10, height: 10)
                        .transition(.scale.combined(with: .opacity))
                }
                Text("Give Lesson")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: resolvedLesson?.id)

            Divider()
                .opacity(0.7)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Lesson selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lesson")
                            .font(.headline)

                        LessonField(
                            lessonSearchText: $lessonSearchText,
                            filteredLessons: filteredLessonsForSearch,
                            lessonDisplayTitle: lessonDisplayTitle(for:),
                            selectedLessonID: selectedLessonIDBinding,
                            isFocused: lessonFocusBinding
                        )

                        if let lesson = resolvedLesson {
                            Text(lessonDisplayTitle(for: lesson))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Choose a lesson to continue.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Students chips row + picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who")
                            .font(.headline)

                        HStack(alignment: .center, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                SelectedStudentsChipsRow(
                                    students: selectedStudentsList,
                                    subjectColor: subjectColor,
                                    displayName: displayName(for:),
                                    onRemove: { id in
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            _ = viewModel.selectedStudentIDs.remove(id)
                                        }
                                    }
                                )
                                .padding(.vertical, 2)
                            }
                            Button {
                                showingStudentPickerPopover = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(subjectColor)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .bottom) {
                                StudentPickerPopoverContent(
                                    studentSearchText: $studentSearchText,
                                    studentLevelFilter: $studentLevelFilter,
                                    filteredStudents: filteredStudentsForPicker,
                                    selectedStudentIDs: Binding(get: { viewModel.selectedStudentIDs }, set: { viewModel.selectedStudentIDs = $0 }),
                                    displayName: displayName(for:),
                                    showingAddStudentSheet: $showingAddStudentSheet,
                                    isPresented: $showingStudentPickerPopover
                                )
                                .padding(12)
                                .frame(minWidth: 320)
                            }
                            .keyboardShortcut("a", modifiers: [.command, .shift])
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.selectedStudentIDs)

                        if viewModel.selectedStudentIDs.isEmpty {
                            Text("Add at least one student.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.mode == .plan && viewModel.scheduledFor == nil {
                            Text("Without a date, this plan appears in Ready to Schedule.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status").font(.headline)

                        HStack {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    viewModel.mode = (viewModel.mode == .plan ? .given : .plan)
                                }
                            }) {
                                Text(viewModel.mode == .plan ? "Plan" : "Given")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(subjectColor.opacity(0.2))
                                    .foregroundStyle(subjectColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut("g", modifiers: [.command, .shift])
                            Spacer()
                        }

                        if viewModel.mode == .plan {
                            OptionalDatePickerRow(
                                toggleLabel: "Schedule",
                                dateLabel: "Schedule For",
                                date: Binding(get: { viewModel.scheduledFor }, set: { viewModel.scheduledFor = $0 })
                            )
                            .animation(.easeInOut, value: viewModel.scheduledFor)
                        } else {
                            OptionalDatePickerRow(
                                toggleLabel: "Include date/time",
                                dateLabel: "Given At",
                                date: Binding(get: { viewModel.givenAt }, set: { viewModel.givenAt = $0 })
                            )
                            .animation(.easeInOut, value: viewModel.givenAt)
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }))
                            .frame(minHeight: 100)
                            .focused($focusedField, equals: .notes)
                    }

                    DisclosureGroup("More options") {
                        HStack(spacing: 8) {
                            TagChip(title: "Practice", isOn: Binding(get: { viewModel.needsPractice }, set: { viewModel.needsPractice = $0 }), color: subjectColor)
                            TagChip(title: "Re‑present", isOn: Binding(get: { viewModel.needsAnotherPresentation }, set: { viewModel.needsAnotherPresentation = $0 }), color: subjectColor)
                        }
                        .padding(.vertical, 4)

                        if showFollowUpField {
                            TextField("Add follow‑up…", text: Binding(get: { viewModel.followUpWork }, set: { viewModel.followUpWork = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .followUp)
                        } else {
                            Button("Add follow‑up…") { showFollowUpField = true }
                                .buttonStyle(.link)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            sortedLessons = viewModel.sortedLessons(from: lessonsSource)
            sortedStudents = viewModel.sortedStudents(from: studentsSource)
        }
        .onDisappear {
            // Proactively clear any popovers/focus that might linger across sheet transitions
            showingStudentPickerPopover = false
            showingAddStudentSheet = false
            focusedField = nil
            lessonSearchText = ""
            showFollowUpField = false
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button(viewModel.mode == .plan ? "Save Plan" : "Mark as Given") {
                    saveStudentLesson()
                }
                .disabled(viewModel.selectedStudentIDs.isEmpty || resolvedLesson == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .alert(saveAlert?.title ?? "Error", isPresented: Binding(get: { saveAlert != nil }, set: { if !$0 { saveAlert = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlert?.message ?? "")
        }
        .overlay(
            KeyboardShortcutsOverlay(
                focusLesson: { focusedField = .lesson },
                openStudents: { showingStudentPickerPopover = true },
                focusNotes: { focusedField = .notes },
                toggleStatus: {
                    withAnimation(.easeInOut) {
                        viewModel.mode = (viewModel.mode == .plan ? .given : .plan)
                    }
                }
            )
        )
        .frame(minWidth: 720, minHeight: 640)
    }
    
    private func saveStudentLesson() {
        guard resolvedLesson != nil else {
            // Inline validation handles missing lesson; no alert.
            return
        }
        do {
            try viewModel.save(context: modelContext, resolvedLesson: resolvedLesson)
            onDone?()
            dismiss()
        } catch let error as GiveLessonViewModel.SaveError {
            switch error {
            case .persistFailed:
                saveAlert = (title: error.title, message: error.localizedDescription)
            case .missingLesson:
                // Handled inline; do nothing.
                break
            }
        } catch {
            saveAlert = (title: "Save Failed", message: error.localizedDescription)
        }
    }
}

final class GiveLessonViewModel: ObservableObject {
    @Published var selectedStudentIDs: Set<UUID>
    @Published var scheduledFor: Date?
    @Published var givenAt: Date?
    @Published var notes: String
    @Published var needsPractice: Bool
    @Published var needsAnotherPresentation: Bool
    @Published var followUpWork: String
    @Published var selectedLessonID: UUID?
    @Published var mode: GiveLessonSheet.Mode

    init(
        selectedStudentIDs: Set<UUID> = [],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        notes: String = "",
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = "",
        selectedLessonID: UUID? = nil,
        mode: GiveLessonSheet.Mode = .plan
    ) {
        self.selectedStudentIDs = selectedStudentIDs
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.selectedLessonID = selectedLessonID
        self.mode = mode
    }
}

extension GiveLessonViewModel {
    enum SaveError: LocalizedError {
        case missingLesson
        case persistFailed(underlying: Error)

        var title: String {
            switch self {
            case .missingLesson: return "Choose a Lesson"
            case .persistFailed: return "Save Failed"
            }
        }

        var errorDescription: String? {
            switch self {
            case .missingLesson:
                return "Please select a lesson before saving."
            case .persistFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    func save(context: ModelContext, resolvedLesson: Lesson?) throws {
        guard let finalLesson = resolvedLesson else {
            throw SaveError.missingLesson
        }

        let studentLesson = StudentLesson(
            lessonID: finalLesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: mode == .plan ? scheduledFor : nil,
            givenAt: mode == .given ? givenAt : nil,
            isPresented: (mode == .given),
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )

        context.insert(studentLesson)

        if needsPractice {
            let existingWorks = try? context.fetch(FetchDescriptor<WorkModel>())
            let hasPractice = (existingWorks ?? []).contains { w in
                w.studentLessonID == studentLesson.id && w.workType == .practice
            }
            if !hasPractice {
                let practiceWork = WorkModel(
                    id: UUID(),
                    studentIDs: Array(selectedStudentIDs),
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                context.insert(practiceWork)
            }
        }

        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let followUp = WorkModel(
                id: UUID(),
                title: "Follow Up: \(finalLesson.name)",
                studentIDs: Array(selectedStudentIDs),
                workType: .followUp,
                studentLessonID: studentLesson.id,
                notes: trimmedFollowUp,
                createdAt: Date()
            )
            context.insert(followUp)
        }

        do {
            try context.save()
        } catch {
            throw SaveError.persistFailed(underlying: error)
        }
    }
}

extension GiveLessonViewModel {
    func sortedLessons(from lessons: [Lesson]) -> [Lesson] {
        lessons.sorted { lhs, rhs in
            if lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedSame {
                if lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
            }
            return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
        }
    }

    func sortedStudents(from students: [Student]) -> [Student] {
        students.sorted { lhs, rhs in
            let l = (lhs.firstName.lowercased(), lhs.lastName.lowercased())
            let r = (rhs.firstName.lowercased(), rhs.lastName.lowercased())
            if l.0 == r.0 { return l.1 < r.1 }
            return l.0 < r.0
        }
    }
}

private struct OptionalDatePickerRow: View {
    let toggleLabel: String
    let dateLabel: String
    @Binding var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(toggleLabel, isOn: Binding(
                get: { date != nil },
                set: { newValue in
                    date = newValue ? (date ?? Date()) : nil
                }
            ))
            if date != nil {
                DatePicker(
                    dateLabel,
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
    }
}

private struct SelectedStudentsChipsRow: View {
    let students: [Student]
    let subjectColor: Color
    let displayName: (Student) -> String
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(students, id: \.id) { student in
                HStack(spacing: 4) {
                    Text(displayName(student))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(subjectColor.opacity(0.2))
                        .foregroundColor(subjectColor)
                        .clipShape(Capsule())
                    Button {
                        onRemove(student.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(subjectColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct StudentPickerPopoverContent: View {
    @Binding var studentSearchText: String
    @Binding var studentLevelFilter: GiveLessonSheet.LevelFilter
    let filteredStudents: [Student]
    @Binding var selectedStudentIDs: Set<UUID>
    let displayName: (Student) -> String
    @Binding var showingAddStudentSheet: Bool
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search and level filter
            TextField("Search students", text: $studentSearchText)
                .textFieldStyle(.roundedBorder)

            Picker("Level", selection: $studentLevelFilter) {
                ForEach(GiveLessonSheet.LevelFilter.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            // Students list with selection checkmarks
            List(filteredStudents, id: \.id) { student in
                Button(action: { toggleSelection(for: student.id) }) {
                    HStack {
                        Text(displayName(student))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedStudentIDs.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minHeight: 200, maxHeight: 360)

            HStack {
                Button {
                    showingAddStudentSheet = true
                    // Optionally close the popover when adding a student
                    isPresented = false
                } label: {
                    Label("Add Student", systemImage: "plus")
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func toggleSelection(for id: UUID) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if selectedStudentIDs.contains(id) {
                _ = selectedStudentIDs.remove(id)
            } else {
                _ = selectedStudentIDs.insert(id)
            }
        }
    }
}

private struct TagChip: View {
    let title: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.2) : Color.secondary.opacity(0.12))
            .foregroundStyle(isOn ? color : .secondary)
            .overlay(
                Capsule().stroke(isOn ? color : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
            .onTapGesture { withAnimation(.easeInOut) { isOn.toggle() } }
    }
}

private struct LessonField: View {
    @Binding var lessonSearchText: String
    let filteredLessons: [Lesson]
    let lessonDisplayTitle: (Lesson) -> String
    @Binding var selectedLessonID: UUID?
    @Binding var isFocused: Bool

    @FocusState private var textFocused: Bool
    @State private var isPresented: Bool = false

    var body: some View {
        TextField("What lesson?", text: $lessonSearchText)
            .textFieldStyle(.roundedBorder)
            .focused($textFocused)
            .onChange(of: isFocused) { newValue in
                textFocused = newValue
                if newValue {
                    withAnimation(.easeInOut) { isPresented = true }
                }
            }
            .onChange(of: textFocused) { newValue in
                isFocused = newValue
            }
            .onTapGesture {
                isFocused = true
                withAnimation(.easeInOut) { isPresented = true }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    List(filteredLessons, id: \.id) { lesson in
                        Button(action: {
                            selectedLessonID = lesson.id
                            lessonSearchText = ""
                            withAnimation(.easeInOut) { isPresented = false }
                            isFocused = false
                        }) {
                            HStack {
                                Text(lessonDisplayTitle(lesson))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedLessonID == lesson.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
                .padding(8)
                #if os(macOS)
                .frame(minWidth: 360, minHeight: 240)
                #endif
            }
            .onDisappear {
                // Ensure popover and focus are cleared when the parent sheet is dismissed
                isPresented = false
                textFocused = false
            }
    }
}

private struct KeyboardShortcutsOverlay: View {
    let focusLesson: () -> Void
    let openStudents: () -> Void
    let focusNotes: () -> Void
    let toggleStatus: () -> Void
    var body: some View {
        ZStack {
            Button(action: focusLesson) { EmptyView() }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: openStudents) { EmptyView() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: focusNotes) { EmptyView() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: toggleStatus) { EmptyView() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .opacity(0.001)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}

