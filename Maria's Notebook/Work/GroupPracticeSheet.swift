import SwiftUI
import SwiftData

/// Sheet for recording a group practice session with multiple students
struct GroupPracticeSheet: View {
    let initialWorkItem: WorkModel
    var onSave: ((PracticeSession) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var allStudents: [Student]
    @Query private var allWork: [WorkModel]
    
    @State private var selectedDate: Date = Date()
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedWorkItemIDs: Set<UUID> = []
    @State private var sharedNotes: String = ""
    @State private var duration: TimeInterval?
    @State private var hasDuration: Bool = false
    @State private var durationMinutes: Int = 30
    @State private var location: String = ""
    @State private var hasLocation: Bool = false
    
    // Individual notes per student (optional)
    @State private var individualNotes: [UUID: String] = [:]
    @State private var showIndividualNotes: Bool = false
    
    private var repository: PracticeSessionRepository {
        PracticeSessionRepository(modelContext: modelContext)
    }
    
    // Students who have the same lesson as the initial work item
    private var suggestedStudents: [Student] {
        guard !initialWorkItem.lessonID.isEmpty else { return [] }
        
        let lessonID = initialWorkItem.lessonID
        let studentIDsWithSameLesson = allWork
            .filter { $0.lessonID == lessonID && $0.id != initialWorkItem.id }
            .map { $0.studentID }
            .compactMap { UUID(uuidString: $0) }
        
        return allStudents
            .filter { studentIDsWithSameLesson.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }
    
    private var selectedStudents: [Student] {
        allStudents
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }
    
    private var selectedWorkItems: [WorkModel] {
        allWork
            .filter { selectedWorkItemIDs.contains($0.id) }
            .sorted { $0.title < $1.title }
    }
    
    private var canSave: Bool {
        !selectedStudentIDs.isEmpty && !selectedWorkItemIDs.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Date selection
                        dateSection
                        
                        Divider()
                        
                        // Currently practicing section
                        currentlyPracticingSection
                        
                        Divider()
                        
                        // Add students section
                        addStudentsSection
                        
                        Divider()
                        
                        // Shared notes
                        sharedNotesSection
                        
                        // Optional fields
                        optionalFieldsSection
                        
                        // Individual notes (expandable)
                        if !selectedStudents.isEmpty {
                            individualNotesSection
                        }
                    }
                    .padding(24)
                }
                
                Divider()
                
                // Bottom bar
                bottomBar
            }
            .navigationTitle("Group Practice Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupInitialState()
            }
        }
    }
    
    // MARK: - View Sections
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice Date")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
    
    private var currentlyPracticingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Currently Practicing")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            ForEach(selectedStudents) { student in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        
                        if let work = selectedWorkItems.first(where: { $0.studentID == student.id.uuidString }) {
                            Text(work.title)
                                .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if selectedStudents.count > 1 {
                        Button {
                            selectedStudentIDs.remove(student.id)
                            if let work = selectedWorkItems.first(where: { $0.studentID == student.id.uuidString }) {
                                selectedWorkItemIDs.remove(work.id)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
    }
    
    private var addStudentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Practice Partners")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            if suggestedStudents.isEmpty {
                emptyPartnersMessage
            } else {
                studentSelectionList
            }
        }
    }
    
    private var emptyPartnersMessage: some View {
        Text("No other students have work for this lesson")
            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .italic()
    }
    
    private var studentSelectionList: some View {
        ForEach(suggestedStudents.filter { !selectedStudentIDs.contains($0.id) }, id: \.id) { student in
            studentSelectionRow(for: student)
        }
    }
    
    private func studentSelectionRow(for student: Student) -> some View {
        Button {
            toggleStudent(student)
        } label: {
            HStack {
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(StudentFormatter.displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if let work = findWorkForStudent(student) {
                        Text(work.title)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var sharedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Notes")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            TextEditor(text: $sharedNotes)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .frame(minHeight: 120)
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
    
    private var optionalFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Duration toggle
            Toggle(isOn: $hasDuration) {
                Text("Track Duration")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
            .onChange(of: hasDuration) { _, newValue in
                if !newValue {
                    duration = nil
                }
            }
            
            if hasDuration {
                HStack {
                    Text("Duration (minutes)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                }
                .padding(.leading, 24)
                .onChange(of: durationMinutes) { _, newValue in
                    duration = TimeInterval(newValue * 60)
                }
            }
            
            // Location toggle
            Toggle(isOn: $hasLocation) {
                Text("Add Location")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
            .onChange(of: hasLocation) { _, newValue in
                if !newValue {
                    location = ""
                }
            }
            
            if hasLocation {
                TextField("Location (e.g., Small table, Outside)", text: $location)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .padding(.leading, 24)
            }
        }
    }
    
    private var individualNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    showIndividualNotes.toggle()
                }
            } label: {
                HStack {
                    Text("Individual Notes")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("(Optional)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: showIndividualNotes ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if showIndividualNotes {
                ForEach(selectedStudents) { student in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        
                        TextEditor(text: Binding(
                            get: { individualNotes[student.id] ?? "" },
                            set: { individualNotes[student.id] = $0 }
                        ))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .frame(minHeight: 60)
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
            }
        }
    }
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                saveSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
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
    
    // MARK: - Helper Methods
    
    private func setupInitialState() {
        // Start with the initial work item's student and work
        if let studentID = UUID(uuidString: initialWorkItem.studentID) {
            selectedStudentIDs.insert(studentID)
        }
        selectedWorkItemIDs.insert(initialWorkItem.id)
    }
    
    private func toggleStudent(_ student: Student) {
        if selectedStudentIDs.contains(student.id) {
            selectedStudentIDs.remove(student.id)
            // Remove their work item too
            if let work = findWorkForStudent(student) {
                selectedWorkItemIDs.remove(work.id)
            }
        } else {
            selectedStudentIDs.insert(student.id)
            // Add their work item
            if let work = findWorkForStudent(student) {
                selectedWorkItemIDs.insert(work.id)
            }
        }
    }
    
    private func findWorkForStudent(_ student: Student) -> WorkModel? {
        allWork.first { work in
            work.studentID == student.id.uuidString &&
            work.lessonID == initialWorkItem.lessonID &&
            work.status != .complete
        }
    }
    
    @MainActor
    private func saveSession() {
        // Create practice session
        let session = repository.create(
            date: selectedDate,
            duration: hasDuration ? duration : nil,
            studentIDs: Array(selectedStudentIDs),
            workItemIDs: Array(selectedWorkItemIDs),
            sharedNotes: sharedNotes,
            location: hasLocation ? location : nil
        )
        
        // Create individual notes if provided
        for (studentID, noteText) in individualNotes {
            guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let note = Note(
                body: noteText,
                scope: .student(studentID),
                category: .academic,
                practiceSession: session
            )
            modelContext.insert(note)
            note.syncStudentLinksIfNeeded(in: modelContext)
        }
        
        try? modelContext.save()
        
        onSave?(session)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Group Practice Sheet") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    // Create sample students
    let mary = Student(firstName: "Mary", lastName: "Smith", birthday: Date(), level: .lower)
    let danny = Student(firstName: "Danny", lastName: "Jones", birthday: Date(), level: .lower)
    let jane = Student(firstName: "Jane", lastName: "Doe", birthday: Date(), level: .lower)
    
    context.insert(mary)
    context.insert(danny)
    context.insert(jane)
    
    // Create sample lesson
    let lesson = Lesson()
    lesson.name = "Long Division"
    lesson.subject = "Math"
    lesson.group = "Operations"
    context.insert(lesson)
    
    // Create sample work items
    let work1 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: danny.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work2 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: mary.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work3 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: jane.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    
    context.insert(work1)
    context.insert(work2)
    context.insert(work3)
    
    return GroupPracticeSheet(initialWorkItem: work1)
        .modelContainer(container)
        .environmentObject(SaveCoordinator())
}
