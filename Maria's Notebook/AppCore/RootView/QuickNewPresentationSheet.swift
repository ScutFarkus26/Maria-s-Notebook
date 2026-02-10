// QuickNewPresentationSheet.swift
// Quick creation sheet for new presentations

import SwiftUI
import SwiftData

struct QuickNewPresentationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

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
    @State private var lessonSearchText: String = ""
    @State private var presentedAt: Date = Date()
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
                    Text("Record Presentation")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    // Lesson Section
                    presentationLessonSection()

                    Divider()

                    // Student Section
                    presentationStudentSection()

                    Divider()

                    // Date Section
                    presentationDateSection()
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { savePresentation() }
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
    private func presentationLessonSection() -> some View {
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
                        selectPresentationLesson(match)
                    }
                }
                .onTapGesture {
                    showingLessonPopover = true
                }
                .popover(isPresented: $showingLessonPopover, arrowEdge: .bottom) {
                    presentationLessonPopoverContent()
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
    private func presentationLessonPopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons.prefix(15), id: \.id) { lesson in
                Button {
                    selectPresentationLesson(lesson)
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

    private func selectPresentationLesson(_ lesson: Lesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false
    }

    // MARK: - Student Section

    private func removePresentationStudent(id: UUID) {
        _ = withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedStudentIDs.remove(id)
        }
    }

    @ViewBuilder
    private func presentationStudentChip(for student: Student) -> some View {
        HStack(spacing: 4) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())

            Button {
                removePresentationStudent(id: student.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func presentationStudentSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Students")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                // Selected students as chips
                if !selectedStudents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedStudents) { student in
                                presentationStudentChip(for: student)
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

    // MARK: - Date Section

    @ViewBuilder
    private func presentationDateSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date")
                .font(.headline)

            DatePicker("Presented on", selection: $presentedAt, displayedComponents: .date)
                .datePickerStyle(.graphical)
        }
    }

    // MARK: - Save

    private func savePresentation() {
        guard let lessonID = selectedLessonID else { return }
        isSaving = true

        let studentUUIDs = Array(selectedStudentIDs)

        // Create LessonAssignment in presented state (the unified presentation model)
        let lessonAssignment = LessonAssignment(
            state: .presented,
            presentedAt: presentedAt,
            lessonID: lessonID,
            studentIDs: studentUUIDs,
            lesson: selectedLesson
        )

        // Snapshot lesson info for historical accuracy
        if let lesson = selectedLesson {
            lessonAssignment.lessonTitleSnapshot = lesson.name
            lessonAssignment.lessonSubheadingSnapshot = lesson.subheading
        }

        modelContext.insert(lessonAssignment)
        saveCoordinator.save(modelContext, reason: "Quick New Presentation")
        dismiss()
    }
}
