import SwiftUI
import SwiftData

struct StudentLessonQuickActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Lesson.name, animation: .default)
    private var lessons: [Lesson]

    @Query(sort: \WorkModel.createdAt, animation: .default)
    private var workModels: [WorkModel]
    
    @Query(sort: \Student.firstName, animation: .default)
    private var studentsAll: [Student]

    @Query(sort: \StudentLesson.createdAt, animation: .default)
    private var studentLessonsAll: [StudentLesson]

    let studentLesson: StudentLesson
    let onDone: (() -> Void)?

    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String
    @State private var presentedNow: Bool = false
    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
    }

    private var lesson: Lesson? {
        lessons.first(where: { $0.id == studentLesson.lessonID })
    }

    private var subject: String {
        (lesson?.subject.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private var group: String {
        (lesson?.group.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private var nextLessonInGroup: Lesson? {
        guard let current = lesson else { return nil }
        let currentSubject = subject
        let currentGroup = group
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        guard let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count else {
            return nil
        }
        return candidates[idx + 1]
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)

            Form {
                Section {
                    Toggle("Presented now", isOn: $presentedNow)
                }

                Section {
                    Toggle("Needs Practice", isOn: $needsPractice)
                    Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
                }

                Section {
                    TextField("Follow Up Work", text: $followUpWork)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Next Lesson in Group")) {
                    if let next = nextLessonInGroup {
                        Text(next.name)
                            .fontWeight(.medium)
                    } else {
                        Text("No next lesson available")
                            .foregroundColor(.secondary)
                    }
                    Button("Plan Next Lesson in Group") {
                        guard let next = nextLessonInGroup else { return }
                        let sameStudents = Set(studentLesson.studentIDs)
                        let exists = studentLessonsAll.contains { sl in
                            sl.lessonID == next.id && Set(sl.studentIDs) == sameStudents && !sl.isGiven
                        }
                        if !exists {
                            let newStudentLesson = StudentLesson(
                                id: UUID(),
                                lessonID: next.id,
                                studentIDs: studentLesson.studentIDs,
                                createdAt: Date(),
                                scheduledFor: nil,
                                givenAt: nil,
                                isPresented: false,
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
                    .disabled(nextLessonInGroup == nil || didPlanNext)
                }
            }
            .frame(minWidth: 360)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)

            HStack(spacing: 24) {
                Button("Cancel") {
                    onDone?() ?? dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .padding(.vertical)
        .overlay(alignment: .top) {
            if showPlannedBanner {
                plannedBanner
            }
        }
    }

    private func saveChanges() {
        if presentedNow {
            studentLesson.isPresented = true
        }
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork

        // Ensure relationships mirror snapshots
        studentLesson.students = studentsAll.filter { studentLesson.studentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == studentLesson.lessonID })
        studentLesson.syncSnapshotsFromRelationships()

        if needsPractice {
            let hasPracticeWork = workModels.contains { work in
                work.studentLessonID == studentLesson.id && work.workType == .practice
            }
            if !hasPracticeWork {
                let practiceWork = WorkModel(
                    id: UUID(),
                    studentIDs: studentLesson.studentIDs,
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                modelContext.insert(practiceWork)
            }
        }

        if needsAnotherPresentation {
            let sameStudents = Set(studentLesson.studentIDs)
            let exists = studentLessonsAll.contains { sl in
                sl.lessonID == studentLesson.lessonID && Set(sl.studentIDs) == sameStudents && !sl.isGiven
            }
            if !exists {
                let newPresentation = StudentLesson(
                    id: UUID(),
                    lessonID: studentLesson.lessonID,
                    studentIDs: studentLesson.studentIDs,
                    createdAt: Date(),
                    scheduledFor: nil,
                    givenAt: nil,
                    isPresented: false,
                    notes: "",
                    needsPractice: false,
                    needsAnotherPresentation: false,
                    followUpWork: ""
                )
                newPresentation.students = studentsAll.filter { studentLesson.studentIDs.contains($0.id) }
                newPresentation.lesson = lessons.first(where: { $0.id == studentLesson.lessonID })
                newPresentation.syncSnapshotsFromRelationships()
                modelContext.insert(newPresentation)
            }
        }

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
                    studentIDs: studentLesson.studentIDs,
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
        } catch {
            // Handle error as appropriate for your app
        }

        onDone?() ?? dismiss()
    }

    private var plannedBanner: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
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
}

#Preview {
    Text("StudentLessonQuickActionsView preview requires real data and cannot run here.")
        .frame(minWidth: 360, minHeight: 240)
        .padding()
}
