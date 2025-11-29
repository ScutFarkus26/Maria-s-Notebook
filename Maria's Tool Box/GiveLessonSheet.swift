import SwiftUI
import SwiftData

struct GiveLessonSheet: View {
    let lesson: Lesson
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]
    
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var scheduledFor: Date? = nil
    @State private var givenAt: Date? = nil
    @State private var notes: String = ""
    @State private var needsPractice: Bool = false
    @State private var needsAnotherPresentation: Bool = false
    @State private var followUpWork: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Give Lesson: \(lesson.name)")
                .font(.title2)
                .bold()
                .padding(.top)
            
            List {
                Section("Select Students") {
                    ForEach(students.sorted(by: { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending })) { s in
                        Toggle(isOn: Binding(
                            get: { selectedStudentIDs.contains(s.id) },
                            set: { newValue in
                                if newValue { selectedStudentIDs.insert(s.id) } else { selectedStudentIDs.remove(s.id) }
                            }
                        )) {
                            Text(s.fullName)
                        }
                    }
                }
                
                Section {
                    Text("This student lesson will be created as unscheduled and appear in Ready to Schedule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                
                Section {
                    Toggle("Needs Practice", isOn: $needsPractice)
                    Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
                }
                
                Section("Follow-up Work") {
                    TextField("Follow-up work", text: $followUpWork)
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    saveStudentLesson()
                }
                .disabled(selectedStudentIDs.isEmpty)
            }
            .padding([.leading, .trailing, .bottom])
        }
        .frame(minWidth: 300, minHeight: 600)
    }
    
    private func saveStudentLesson() {
        let studentLesson = StudentLesson(
            lessonID: lesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: nil,
            givenAt: nil,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )
        
        modelContext.insert(studentLesson)
        do {
            try modelContext.save()
            onDone?()
            dismiss()
        } catch {
            // could add error handling here
        }
    }
}

#Preview {
    Text("GiveLessonSheet preview requires app data and context to display properly.")
}
