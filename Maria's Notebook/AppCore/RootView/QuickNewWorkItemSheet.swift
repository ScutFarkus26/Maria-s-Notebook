// QuickNewWorkItemSheet.swift
// Quick creation sheet for new work items

import SwiftUI
import SwiftData

struct QuickNewWorkItemSheet: View {
    /// Optional callback when work is created and user wants to view details immediately
    var onCreatedAndOpen: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    private var allLessons: [Lesson]

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(allStudentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var selectedLessonID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var workTitle: String = ""
    @State private var workKind: WorkKind = .practiceLesson
    @State private var dueDate: Date? = nil
    @State private var hasDueDate: Bool = false
    @State private var lessonSearchText: String = ""
    @State private var isSaving: Bool = false

    // Popover states
    @State private var showingLessonPopover: Bool = false
    @State private var showingStudentPopover: Bool = false
    @FocusState private var lessonFieldFocused: Bool

    private var filteredLessons: [Lesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allLessons }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }

    private var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }

    private var canSave: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("New Work")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    // Lesson Section
                    lessonSection()

                    Divider()

                    // Student Section
                    studentSection()

                    Divider()

                    // Details Section
                    detailsSection()
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if onCreatedAndOpen != nil && selectedStudentIDs.count == 1 {
                    Button("Create & Open") { saveWorkItem(andOpen: true) }
                        .disabled(!canSave || isSaving)
                }
                Button("Create") { saveWorkItem(andOpen: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
            }
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    // MARK: - Lesson Section

    @ViewBuilder
    private func lessonSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lesson")
                .font(.headline)

            // Search field with popover
            TextField("Search lessons...", text: $lessonSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($lessonFieldFocused)
                .onChange(of: lessonSearchText) { _, newValue in
                    if !newValue.trimmed().isEmpty {
                        showingLessonPopover = true
                    }
                }
                .onSubmit {
                    // If user typed an exact lesson name, select it
                    let trimmed = lessonSearchText.trimmed()
                    if let match = filteredLessons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        selectLesson(match)
                    }
                }
                .onTapGesture {
                    showingLessonPopover = true
                }
                .popover(isPresented: $showingLessonPopover, arrowEdge: .bottom) {
                    lessonPopoverContent()
                }

            // Selected lesson display
            if let lesson = selectedLesson {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.name)
                            .font(.subheadline.weight(.semibold))
                        if !lesson.subject.isEmpty {
                            Text(lesson.subject)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        selectedLessonID = nil
                        lessonSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            } else {
                Text("Choose a lesson to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func lessonPopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons.prefix(15), id: \.id) { lesson in
                Button {
                    selectLesson(lesson)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.name)
                                .foregroundStyle(.primary)
                            if !lesson.subject.isEmpty {
                                Text("\(lesson.subject) • \(lesson.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            #if os(macOS)
            .focusable(false)
            #endif
        }
        .padding(8)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #else
        .frame(minHeight: 300)
        #endif
    }

    private func selectLesson(_ lesson: Lesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false

        // Auto-set work title if empty
        if workTitle.isEmpty {
            workTitle = lesson.name
        }
    }

    // MARK: - Student Section

    private func removeStudent(id: UUID) {
        _ = withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedStudentIDs.remove(id)
        }
    }

    @ViewBuilder
    private func studentChip(for student: Student) -> some View {
        HStack(spacing: 4) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())

            Button {
                removeStudent(id: student.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func studentSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Student")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                // Selected students as chips
                if !selectedStudents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedStudents) { student in
                                studentChip(for: student)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Add student button
                Button {
                    showingStudentPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStudentPopover, arrowEdge: .bottom) {
                    StudentPickerPopover(
                        students: allStudents,
                        selectedIDs: $selectedStudentIDs,
                        onDone: { showingStudentPopover = false }
                    )
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedStudentIDs)

            if selectedStudentIDs.isEmpty {
                Text("Add at least one student.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            TextField("Title (optional)", text: $workTitle)
                .textFieldStyle(.roundedBorder)

            // Work Kind picker as segmented buttons
            HStack(spacing: 0) {
                kindButton(.practiceLesson, "Practice")
                kindButton(.followUpAssignment, "Follow-Up")
                kindButton(.research, "Project")
                kindButton(.report, "Report")
            }
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

            // Due date toggle and picker
            Toggle("Set due date", isOn: $hasDueDate)
                .onChange(of: hasDueDate) { _, newValue in
                    if newValue {
                        if dueDate == nil {
                            dueDate = AppCalendar.startOfDay(Date())
                        }
                    } else {
                        dueDate = nil
                    }
                }

            if hasDueDate {
                DatePicker("Due date", selection: Binding(
                    get: { dueDate ?? AppCalendar.startOfDay(Date()) },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private func kindButton(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(workKind == kind ? Color.accentColor.opacity(0.1) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
        .font(.subheadline)
    }

    // MARK: - Save

    private func saveWorkItem(andOpen: Bool) {
        guard let lessonID = selectedLessonID,
              !selectedStudentIDs.isEmpty else { return }
        isSaving = true

        let repository = WorkRepository(context: modelContext)

        do {
            var createdWorkID: UUID?
            // Create work for each selected student
            for studentID in selectedStudentIDs {
                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: lessonID,
                    title: workTitle.isEmpty ? nil : workTitle,
                    kind: workKind,
                    scheduledDate: hasDueDate ? dueDate : nil
                )
                // Keep reference to first created work for "Create & Open"
                if createdWorkID == nil {
                    createdWorkID = work.id
                }
            }
            _ = saveCoordinator.save(modelContext, reason: "Quick New Work Item")
            dismiss()

            // If user wants to open the detail view, call the callback after dismiss
            if andOpen, let workID = createdWorkID {
                onCreatedAndOpen?(workID)
            }
        } catch {
            isSaving = false
        }
    }
}
