import SwiftUI
import SwiftData

struct StudentLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]

    let studentLesson: StudentLesson
    var onDone: (() -> Void)? = nil

    @State private var scheduledFor: Date?
    @State private var givenAt: Date?
    @State private var notes: String
    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        _scheduledFor = State(initialValue: studentLesson.scheduledFor)
        _givenAt = State(initialValue: studentLesson.givenAt)
        _notes = State(initialValue: studentLesson.notes)
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Lesson")) {
                    Text(lessons.first(where: { $0.id == studentLesson.lessonID })?.name ?? "Lesson")
                        .font(.headline)
                }

                Section(header: Text("Students")) {
                    let associatedStudents = studentsAll.filter { studentLesson.studentIDs.contains($0.id) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(associatedStudents, id: \.id) { student in
                                Text(student.fullName)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.accentColor.opacity(0.2))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Scheduled For") {
                    Toggle("Scheduled", isOn: Binding(
                        get: { scheduledFor != nil },
                        set: { newValue in
                            if newValue {
                                scheduledFor = scheduledFor ?? Date()
                            } else {
                                scheduledFor = nil
                            }
                        }))
                    if let date = scheduledFor {
                        DatePicker("Date", selection: Binding(
                            get: { date },
                            set: { scheduledFor = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Given At") {
                    Toggle("Given", isOn: Binding(
                        get: { givenAt != nil },
                        set: { newValue in
                            if newValue {
                                givenAt = givenAt ?? Date()
                            } else {
                                givenAt = nil
                            }
                        }))
                    if let date = givenAt {
                        DatePicker("Date", selection: Binding(
                            get: { date },
                            set: { givenAt = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                Section("Follow Up Work") {
                    TextField("Follow Up Work", text: $followUpWork)
                }

                Section {
                    Toggle("Needs Practice", isOn: $needsPractice)
                    Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
                }
            }
            .navigationTitle("Lesson Details")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button(role: .destructive) {
                            delete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Spacer()

                        Button("Cancel") {
                            dismiss()
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
        }
    }

    private func save() {
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork

        do {
            try modelContext.save()
            onDone?() ?? dismiss()
        } catch {
            // Handle save error if needed
        }
    }

    private func delete() {
        modelContext.delete(studentLesson)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Handle delete error if needed
        }
    }
}

#Preview {
    Text("StudentLessonDetailView preview requires real model data")
}
