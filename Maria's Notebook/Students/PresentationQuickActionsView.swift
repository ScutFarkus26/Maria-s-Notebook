import OSLog
import SwiftData
import SwiftUI

private let logger = Logger.students

struct PresentationQuickActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: \Lesson.name, animation: .default)
    private var lessons: [Lesson]

    @Query(sort: \Student.firstName, animation: .default)
    private var studentsAllRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var studentsAll: [Student] {
        TestStudentsFilter.filterVisible(studentsAllRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @Query(sort: \LessonAssignment.createdAt, animation: .default)
    private var lessonAssignmentsAll: [LessonAssignment]

    let lessonAssignment: LessonAssignment
    let onDone: (() -> Void)?

    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String
    @State private var presentedNow: Bool = false
    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false

    @State private var showFollowUpSheet: Bool = false
    @State private var followUpDraft: String = ""

    init(lessonAssignment: LessonAssignment, onDone: (() -> Void)? = nil) {
        self.lessonAssignment = lessonAssignment
        self.onDone = onDone
        _needsPractice = State(initialValue: lessonAssignment.needsPractice)
        _needsAnotherPresentation = State(initialValue: lessonAssignment.needsAnotherPresentation)
        _followUpWork = State(initialValue: lessonAssignment.followUpWork)
    }

    private var lesson: Lesson? {
        // CloudKit compatibility: lessonID is now String, convert to UUID for comparison
        guard let lessonIDUUID = UUID(uuidString: lessonAssignment.lessonID) else { return nil }
        return lessons.first(where: { $0.id == lessonIDUUID })
    }

    private var subject: String {
        (lesson?.subject.trimmed()) ?? ""
    }

    private var group: String {
        (lesson?.group.trimmed()) ?? ""
    }

    private var nextLessonInGroup: Lesson? {
        guard let current = lesson else { return nil }
        let currentSubject = subject
        let currentGroup = group
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        let candidates = lessons.filter { l in
            l.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
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
                            .foregroundStyle(.secondary)
                    }
                    Button("Plan Next Lesson in Group") {
                        guard let next = nextLessonInGroup else { return }
                        // Do not create or plan lessons for zero students
                        guard !lessonAssignment.resolvedStudentIDs.isEmpty else { return }
                        let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
                        let exists = lessonAssignmentsAll.contains { la in
                            la.resolvedLessonID == next.id && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
                        }
                        if !exists {
                            let newLA = PresentationFactory.makeDraft(
                                lessonID: next.id,
                                studentIDs: lessonAssignment.resolvedStudentIDs
                            )
                            PresentationFactory.attachRelationships(
                                to: newLA,
                                lesson: lessons.first(where: { $0.id == next.id }),
                                students: studentsAll.filter { sameStudents.contains($0.id) }
                            )
                            modelContext.insert(newLA)
                            saveCoordinator.save(modelContext, reason: "Planning next lesson")
                        }
                        didPlanNext = true
                        showPlannedBanner = true
                        Task { @MainActor in
                            do {
                                try await Task.sleep(for: .seconds(2))
                            } catch {
                                logger.warning("showPlannedBanner task sleep interrupted: \(error)")
                            }
                            showPlannedBanner = false
                        }
                    }
                    .disabled(nextLessonInGroup == nil || didPlanNext || lessonAssignment.resolvedStudentIDs.isEmpty)
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
                        let trimmed = followUpDraft.trimmed()
                        if !trimmed.isEmpty {
                            let sidStrings = lessonAssignment.resolvedStudentIDs.map { $0.uuidString }
                            // CloudKit compatibility: lessonID is already String
                            let lidString = lessonAssignment.lessonID
                            for sid in sidStrings {
                                // De-dupe by (student, lesson, kind=followUp) in active/review
                                let activeRaw = WorkStatus.active.rawValue
                                let reviewRaw = WorkStatus.review.rawValue
                                let followRaw = WorkKind.followUpAssignment.rawValue
                                let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> {
                                    $0.studentID == sid &&
                                    $0.lessonID == lidString &&
                                    ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) &&
                                    ($0.kindRaw ?? "") == followRaw
                                })
                                let exists = modelContext.safeFetchFirst(fetch) != nil
                                if !exists {
                                    // Create WorkModel
                                    guard let studentUUID = UUID(uuidString: sid),
                                          let lessonUUID = UUID(uuidString: lidString) else { continue }
                                    let repository = WorkRepository(context: modelContext)
                                    do {
                                        let workModel = try repository.createWork(
                                            studentID: studentUUID,
                                            lessonID: lessonUUID,
                                            title: trimmed,
                                            kind: .followUpAssignment,
                                            presentationID: nil,
                                            scheduledDate: nil
                                        )
                                        workModel.setLegacyNoteText(trimmed, in: modelContext)
                                    } catch {
                                        logger.warning("Failed to create follow-up work: \(error)")
                                    }
                                }
                            }
                            saveCoordinator.save(modelContext, reason: "Adding follow-up work")
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
            let presentedDate = AppCalendar.startOfDay(Date())
            lessonAssignment.markPresented(at: presentedDate)
            do {
                _ = try LifecycleService.recordPresentation(
                    from: lessonAssignment,
                    presentedAt: presentedDate,
                    modelContext: modelContext
                )
            } catch {
                // ignore
            }

            // Auto-enroll in track if lesson belongs to a track
            if let lesson = lessonAssignment.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson,
                    studentIDs: lessonAssignment.studentIDs,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        // Phase 3: Auto-create next lesson in group when marking presented now
        if presentedNow, let lessonIDUUID = UUID(uuidString: lessonAssignment.lessonID),
           let current = lessons.first(where: { $0.id == lessonIDUUID }) {
            let currentSubject = current.subject.trimmed()
            let currentGroup = current.group.trimmed()
            if !currentSubject.isEmpty, !currentGroup.isEmpty {
                let candidates = lessons.filter { l in
                    l.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
                    l.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
                }
                .sorted { $0.orderInGroup < $1.orderInGroup }
                if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
                    let next = candidates[idx + 1]
                    let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
                    // Skip if there are no students attached
                    guard !sameStudents.isEmpty else { return }
                    let exists = lessonAssignmentsAll.contains { la in
                        la.resolvedLessonID == next.id && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
                    }
                    if !exists {
                        let newLA = PresentationFactory.makeDraft(
                            lessonID: next.id,
                            studentIDs: Array(sameStudents)
                        )
                        PresentationFactory.attachRelationships(
                            to: newLA,
                            lesson: lessons.first(where: { $0.id == next.id }),
                            students: studentsAll.filter { sameStudents.contains($0.id) }
                        )
                        modelContext.insert(newLA)
                        saveCoordinator.save(modelContext, reason: "Auto-creating next lesson")
                        appRouter.refreshPlanningInbox()
                    }
                }
            }
        }

        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation

        // Ensure relationships mirror snapshots
        lessonAssignment.students = studentsAll.filter { lessonAssignment.resolvedStudentIDs.contains($0.id) }
        if let lessonIDUUID = UUID(uuidString: lessonAssignment.lessonID) {
            lessonAssignment.lesson = lessons.first(where: { $0.id == lessonIDUUID })
        }

        if needsAnotherPresentation {
            // Skip creating follow-up if zero students
            guard !lessonAssignment.resolvedStudentIDs.isEmpty else { return }
            let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
            let currentLessonID = lessonAssignment.resolvedLessonID
            let exists = lessonAssignmentsAll.contains { la in
                la.resolvedLessonID == currentLessonID && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
            }
            if !exists {
                let newLA = PresentationFactory.makeDraft(
                    lessonID: currentLessonID,
                    studentIDs: lessonAssignment.resolvedStudentIDs
                )
                PresentationFactory.attachRelationships(
                    to: newLA,
                    lesson: UUID(uuidString: lessonAssignment.lessonID).flatMap { lid in lessons.first(where: { $0.id == lid }) },
                    students: studentsAll.filter { lessonAssignment.resolvedStudentIDs.contains($0.id) }
                )
                modelContext.insert(newLA)
            }
        }

        saveCoordinator.save(modelContext, reason: "Saving quick actions")

        onDone?() ?? dismiss()
    }

    private func addPracticeIfNeeded() {
        // Create practice contracts if none exist for these students/lesson
        let sidStrings = lessonAssignment.resolvedStudentIDs.map { $0.uuidString }
        // CloudKit compatibility: lessonID is already String
        let lidString = lessonAssignment.lessonID
        var createdAny = false
        for sid in sidStrings {
            let activeRaw = WorkStatus.active.rawValue
            let reviewRaw = WorkStatus.review.rawValue
            let practiceRaw = WorkKind.practiceLesson.rawValue
            let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> {
                $0.studentID == sid &&
                $0.lessonID == lidString &&
                ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) &&
                ($0.kindRaw ?? "") == practiceRaw
            })
            let exists = modelContext.safeFetchFirst(fetch) != nil
            if !exists {
                // Create WorkModel
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lidString) else { continue }
                let repository = WorkRepository(context: modelContext)
                do {
                    _ = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonUUID,
                        title: nil,
                        kind: .practiceLesson,
                        presentationID: nil,
                        scheduledDate: nil
                    )
                    createdAny = true
                } catch {
                    logger.warning("Failed to create practice work: \(error)")
                }
            }
        }
        if createdAny { saveCoordinator.save(modelContext, reason: "Adding practice work") }
    }

    private var plannedBanner: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.95))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}

#Preview {
    Text("PresentationQuickActionsView preview requires real SwiftData context and cannot run here.")
        .frame(minWidth: 360, minHeight: 240)
        .padding()
}
