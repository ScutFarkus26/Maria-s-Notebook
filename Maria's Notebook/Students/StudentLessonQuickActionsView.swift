import SwiftUI
import SwiftData

struct StudentLessonQuickActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Lesson.name, animation: .default)
    private var lessons: [Lesson]
    
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

    @State private var showFollowUpSheet: Bool = false
    @State private var followUpDraft: String = ""

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
    }

    private var lesson: Lesson? {
        // CloudKit compatibility: lessonID is now String, convert to UUID for comparison
        guard let lessonIDUUID = UUID(uuidString: studentLesson.lessonID) else { return nil }
        return lessons.first(where: { $0.id == lessonIDUUID })
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
                    Button("Add Practice", systemImage: "arrow.triangle.2.circlepath") {
                        addPracticeIfNeeded()
                    }
                    Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
                }

                Section(header: Text("Follow Up")) {
                    Button("Add Follow-Up…", systemImage: "plus") {
                        showFollowUpSheet = true
                    }
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
                        // Do not create or plan lessons for zero students
                        guard !studentLesson.resolvedStudentIDs.isEmpty else { return }
                        let sameStudents = Set(studentLesson.resolvedStudentIDs)
                        let exists = studentLessonsAll.contains { sl in
                            sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && !sl.isGiven
                        }
                        if !exists {
                            let newStudentLesson = StudentLesson(
                                id: UUID(),
                                lessonID: next.id,
                                studentIDs: studentLesson.resolvedStudentIDs,
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
                            modelContext.insert(newStudentLesson)
                            try? modelContext.save()
                        }
                        didPlanNext = true
                        showPlannedBanner = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showPlannedBanner = false
                        }
                    }
                    .disabled(nextLessonInGroup == nil || didPlanNext || studentLesson.resolvedStudentIDs.isEmpty)
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
        .sheet(isPresented: $showFollowUpSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Follow-Up")
                    .font(.headline)
                TextField("Describe follow-up work…", text: $followUpDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showFollowUpSheet = false }
                    Button("Add") {
                        let trimmed = followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let sidStrings = studentLesson.resolvedStudentIDs.map { $0.uuidString }
                            // CloudKit compatibility: lessonID is already String
                            let lidString = studentLesson.lessonID
                            for sid in sidStrings {
                                // De-dupe by (student, lesson, kind=followUp) in active/review
                                let activeRaw = WorkStatus.active.rawValue
                                let reviewRaw = WorkStatus.review.rawValue
                                let followRaw = WorkKind.followUpAssignment.rawValue
                                let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> {
                                    $0.studentID == sid &&
                                    $0.lessonID == lidString &&
                                    ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) &&
                                    ($0.kindRaw ?? "") == followRaw
                                })
                                let exists = ((try? modelContext.fetch(fetch)) ?? []).first != nil
                                if !exists {
                                    let c = WorkContract(studentID: sid, lessonID: lidString, status: .active)
                                    c.kind = .followUpAssignment
                                    c.scheduledNote = trimmed
                                    modelContext.insert(c)
                                }
                            }
                            try? modelContext.save()
                        }
                        showFollowUpSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            #if os(macOS)
            .frame(minWidth: 420)
            .presentationSizingFitted()
            #endif
        }
    }

    private func saveChanges() {
        if presentedNow {
            studentLesson.isPresented = true
            do {
                let presentedDate = AppCalendar.startOfDay(Date())
                _ = try LifecycleService.recordPresentationAndExplodeWork(
                    from: studentLesson,
                    presentedAt: presentedDate,
                    modelContext: modelContext
                )
            } catch {
                // ignore
            }
        }

        // Phase 3: Auto-create next lesson in group when marking presented now
        if presentedNow, let lessonIDUUID = UUID(uuidString: studentLesson.lessonID),
           let current = lessons.first(where: { $0.id == lessonIDUUID }) {
            let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentSubject.isEmpty, !currentGroup.isEmpty {
                let candidates = lessons.filter { l in
                    l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
                    l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
                }
                .sorted { $0.orderInGroup < $1.orderInGroup }
                if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
                    let next = candidates[idx + 1]
                    let sameStudents = Set(studentLesson.resolvedStudentIDs)
                    // Skip if there are no students attached
                    guard !sameStudents.isEmpty else { return }
                    let exists = studentLessonsAll.contains { sl in
                        sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
                    }
                    if !exists {
                        let newSL = StudentLesson(
                            id: UUID(),
                            lessonID: next.id,
                            studentIDs: Array(sameStudents),
                            createdAt: Date(),
                            scheduledFor: nil,
                            givenAt: nil,
                            isPresented: false,
                            notes: "",
                            needsPractice: false,
                            needsAnotherPresentation: false,
                            followUpWork: ""
                        )
                        newSL.students = studentsAll.filter { sameStudents.contains($0.id) }
                        newSL.lesson = lessons.first(where: { $0.id == next.id })
                        modelContext.insert(newSL)
                        try? modelContext.save()
                        appRouter.refreshPlanningInbox()
                    }
                }
            }
        }

        // Remove legacy fields and auto-create blocks for practice and follow-up

        studentLesson.needsAnotherPresentation = needsAnotherPresentation

        // Ensure relationships mirror snapshots
        studentLesson.students = studentsAll.filter { studentLesson.resolvedStudentIDs.contains($0.id) }
        if let lessonIDUUID = UUID(uuidString: studentLesson.lessonID) {
            studentLesson.lesson = lessons.first(where: { $0.id == lessonIDUUID })
        }

        if needsAnotherPresentation {
            // Skip creating follow-up if zero students
            guard !studentLesson.resolvedStudentIDs.isEmpty else { return }
            let sameStudents = Set(studentLesson.resolvedStudentIDs)
            let currentLessonID = studentLesson.resolvedLessonID
            let exists = studentLessonsAll.contains { sl in
                sl.resolvedLessonID == currentLessonID && Set(sl.resolvedStudentIDs) == sameStudents && !sl.isGiven
            }
            if !exists {
                let newPresentation = StudentLesson(
                    id: UUID(),
                    lessonID: currentLessonID,
                    studentIDs: studentLesson.resolvedStudentIDs,
                    createdAt: Date(),
                    scheduledFor: nil,
                    givenAt: nil,
                    isPresented: false,
                    notes: "",
                    needsPractice: false,
                    needsAnotherPresentation: false,
                    followUpWork: ""
                )
                newPresentation.students = studentsAll.filter { studentLesson.resolvedStudentIDs.contains($0.id) }
                if let lessonIDUUID = UUID(uuidString: studentLesson.lessonID) {
                    newPresentation.lesson = lessons.first(where: { $0.id == lessonIDUUID })
                }
                modelContext.insert(newPresentation)
            }
        }

        do {
            try modelContext.save()
        } catch {
            // Handle error as appropriate for your app
        }

        onDone?() ?? dismiss()
    }

    private func addPracticeIfNeeded() {
        // Create practice contracts if none exist for these students/lesson
        let sidStrings = studentLesson.resolvedStudentIDs.map { $0.uuidString }
        // CloudKit compatibility: lessonID is already String
        let lidString = studentLesson.lessonID
        var createdAny = false
        for sid in sidStrings {
            let activeRaw = WorkStatus.active.rawValue
            let reviewRaw = WorkStatus.review.rawValue
            let practiceRaw = WorkKind.practiceLesson.rawValue
            let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> {
                $0.studentID == sid &&
                $0.lessonID == lidString &&
                ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) &&
                ($0.kindRaw ?? "") == practiceRaw
            })
            let exists = ((try? modelContext.fetch(fetch)) ?? []).first != nil
            if !exists {
                let c = WorkContract(studentID: sid, lessonID: lidString, status: .active)
                c.kind = .practiceLesson
                modelContext.insert(c)
                createdAny = true
            }
        }
        if createdAny { try? modelContext.save() }
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

