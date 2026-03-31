import SwiftUI
import CoreData

/// Quick sheet for adding a lesson to a student's inbox from the meetings view
struct AddLessonToInboxSheet: View {
    let student: CDStudent
    var preselectedLessonID: UUID?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true), NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>
    
    @State private var selectedLessonID: UUID?
    @State private var lessonSearchText: String = ""
    @State private var isSaving: Bool = false
    
    // Popover state
    @State private var showingLessonPopover: Bool = false
    @FocusState private var lessonFieldFocused: Bool
    
    private var filteredLessons: [CDLesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(allLessons) }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }
    
    private var selectedLesson: CDLesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }
    
    private var canSave: Bool {
        selectedLessonID != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add CDLesson to Inbox")
                            .font(AppTheme.ScaledFont.titleXLarge)
                        
                        HStack(spacing: 6) {
                            Text("For:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(StudentFormatter.displayName(for: student))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    Divider()
                    
                    // CDLesson Section
                    lessonSection()
                }
                .padding(24)
            }
            
            Divider()
            
            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add to Inbox") { saveLessonToInbox() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
            }
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 450, minHeight: 400)
        #endif
        .onAppear {
            if let preselectedID = preselectedLessonID,
               let lesson = allLessons.first(where: { $0.id == preselectedID }) {
                selectedLessonID = preselectedID
                lessonSearchText = lesson.name
            }
        }
    }
    
    // MARK: - CDLesson Section
    
    @ViewBuilder
    // swiftlint:disable:next function_body_length
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
                    if let match = filteredLessons.first(where: {
                        $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }) {
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
                            .font(.subheadline.weight(.bold))
                        HStack(spacing: 4) {
                            if !lesson.subject.isEmpty {
                                Text(lesson.subject)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !lesson.group.isEmpty {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(lesson.group)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                .cornerRadius(8)
            } else {
                Text("Choose a lesson to add to the inbox.")
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
                                .foregroundStyle(Color.accentColor)
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
    
    private func selectLesson(_ lesson: CDLesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false
    }
    
    // MARK: - Save
    
    private func saveLessonToInbox() {
        guard let lessonID = selectedLessonID else { return }
        isSaving = true
        
        // Create a draft CDLessonAssignment (inbox item)
        guard let studentID = student.id else { return }
        let draft = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])
        viewContext.insert(draft)
        saveCoordinator.save(viewContext, reason: "Add Lesson to Inbox from Meeting")
        dismiss()
    }
}
