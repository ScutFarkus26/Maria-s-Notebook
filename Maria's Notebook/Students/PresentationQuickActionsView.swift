import OSLog
import SwiftUI
import CoreData

private let logger = Logger.students

// swiftlint:disable:next type_body_length
struct PresentationQuickActionsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)], animation: .default)
    private var lessons: FetchedResults<CDLesson>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)], animation: .default)
    private var studentsAllRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var studentsAll: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsAllRaw).uniqueByID, show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: true)], animation: .default)
    private var lessonAssignmentsAll: FetchedResults<CDLessonAssignment>

    let lessonAssignment: CDLessonAssignment
    let onDone: (() -> Void)?

    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String
    @State private var presentedNow: Bool = false
    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false

    @State private var showFollowUpSheet: Bool = false
    @State private var followUpDraft: String = ""

    init(lessonAssignment: CDLessonAssignment, onDone: (() -> Void)? = nil) {
        self.lessonAssignment = lessonAssignment
        self.onDone = onDone
        _needsPractice = State(initialValue: lessonAssignment.needsPractice)
        _needsAnotherPresentation = State(initialValue: lessonAssignment.needsAnotherPresentation)
        _followUpWork = State(initialValue: lessonAssignment.followUpWork)
    }

    private var lesson: CDLesson? {
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

    private var nextLessonInGroup: CDLesson? {
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

                Section(header: Text("Next CDLesson in Group")) {
                    if let next = nextLessonInGroup {
                        Text(next.name)
                            .fontWeight(.medium)
                    } else {
                        Text("No next lesson available")
                            .foregroundStyle(.secondary)
                    }
                    Button("Plan Next CDLesson in Group") {
                        guard let next = nextLessonInGroup else { return }
                        // Do not create or plan lessons for zero students
                        guard !lessonAssignment.resolvedStudentIDs.isEmpty else { return }
                        let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
                        guard let nextID = next.id else { return }
                        let exists = lessonAssignmentsAll.contains { la in
                            la.resolvedLessonID == nextID
                                && Set(la.resolvedStudentIDs) == sameStudents
                                && !la.isPresented
                        }
                        if !exists {
                            let nextLesson = lessons.first(where: { $0.id == nextID })
                            let nextStudents = studentsAll.filter { $0.id.map { sameStudents.contains($0) } ?? false }
                            if let nextLesson {
                                _ = PresentationFactory.makeDraft(
                                    lesson: nextLesson, students: nextStudents, context: viewContext
                                )
                            } else {
                                _ = PresentationFactory.makeDraft(
                                    lessonID: nextID, studentIDs: lessonAssignment.resolvedStudentIDs, context: viewContext
                                )
                            }
                            saveCoordinator.save(viewContext, reason: "Planning next lesson")
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
                            let sidStrings = lessonAssignment.resolvedStudentIDs.map(\.uuidString)
                            // CloudKit compatibility: lessonID is already String
                            let lidString = lessonAssignment.lessonID
                            for sid in sidStrings {
                                // De-dupe by (student, lesson, kind=followUp) in active/review
                                let activeRaw = WorkStatus.active.rawValue
                                let reviewRaw = WorkStatus.review.rawValue
                                let followRaw = WorkKind.followUpAssignment.rawValue
                                let fetch: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
                                fetch.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@ AND (statusRaw == %@ OR statusRaw == %@) AND kindRaw == %@", sid, lidString, activeRaw, reviewRaw, followRaw)
                                let exists = viewContext.safeFetchFirst(fetch) != nil
                                if !exists {
                                    // Create CDWorkModel
                                    guard let studentUUID = UUID(uuidString: sid),
                                          let lessonUUID = UUID(uuidString: lidString) else { continue }
                                    let repository = WorkRepository(context: managedObjectContext)
                                    do {
                                        let workModel = try repository.createWork(
                                            studentID: studentUUID,
                                            lessonID: lessonUUID,
                                            title: trimmed,
                                            kind: .followUpAssignment,
                                            presentationID: nil,
                                            scheduledDate: nil
                                        )
                                        workModel.setLegacyNoteText(trimmed, in: managedObjectContext)
                                    } catch {
                                        logger.warning("Failed to create follow-up work: \(error)")
                                    }
                                }
                            }
                            saveCoordinator.save(viewContext, reason: "Adding follow-up work")
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func saveChanges() {
        if presentedNow {
            let presentedDate = AppCalendar.startOfDay(Date())
            lessonAssignment.markPresented(at: presentedDate)
            do {
                _ = try LifecycleService.recordPresentation(
                    from: lessonAssignment,
                    presentedAt: presentedDate,
                    modelContext: viewContext
                )
            } catch {
                // ignore
            }

            // Auto-enroll in track if lesson belongs to a track
            if let lesson = lessonAssignment.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject,
                    lessonGroup: lesson.group,
                    studentIDs: lessonAssignment.studentIDs,
                    context: viewContext,
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
                    guard let nextID = next.id else { return }
                    let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
                    // Skip if there are no students attached
                    guard !sameStudents.isEmpty else { return }
                    let exists = lessonAssignmentsAll.contains { la in
                        la.resolvedLessonID == nextID && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
                    }
                    if !exists {
                        let nextLesson = lessons.first(where: { $0.id == nextID })
                        let nextStudents = studentsAll.filter { $0.id.map { sameStudents.contains($0) } ?? false }
                        if let nextLesson {
                            _ = PresentationFactory.makeDraft(
                                lesson: nextLesson, students: nextStudents, context: viewContext
                            )
                        } else {
                            _ = PresentationFactory.makeDraft(
                                lessonID: nextID, studentIDs: Array(sameStudents), context: viewContext
                            )
                        }
                        saveCoordinator.save(viewContext, reason: "Auto-creating next lesson")
                        appRouter.refreshPlanningInbox()
                    }
                }
            }
        }

        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation

        // Ensure lesson relationship mirrors snapshot
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
                let currentLesson = UUID(uuidString: lessonAssignment.lessonID)
                    .flatMap { lid in lessons.first(where: { $0.id == lid }) }
                let currentStudents = studentsAll.filter { s in s.id.map { lessonAssignment.resolvedStudentIDs.contains($0) } ?? false }
                if let currentLesson {
                    _ = PresentationFactory.makeDraft(
                        lesson: currentLesson, students: currentStudents, context: viewContext
                    )
                } else {
                    _ = PresentationFactory.makeDraft(
                        lessonID: currentLessonID, studentIDs: lessonAssignment.resolvedStudentIDs, context: viewContext
                    )
                }
            }
        }

        saveCoordinator.save(viewContext, reason: "Saving quick actions")

        onDone?() ?? dismiss()
    }

    private func addPracticeIfNeeded() {
        // Create practice contracts if none exist for these students/lesson
        let sidStrings = lessonAssignment.resolvedStudentIDs.map(\.uuidString)
        // CloudKit compatibility: lessonID is already String
        let lidString = lessonAssignment.lessonID
        var createdAny = false
        for sid in sidStrings {
            let activeRaw = WorkStatus.active.rawValue
            let reviewRaw = WorkStatus.review.rawValue
            let practiceRaw = WorkKind.practiceLesson.rawValue
            let fetch: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
            fetch.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@ AND (statusRaw == %@ OR statusRaw == %@) AND kindRaw == %@", sid, lidString, activeRaw, reviewRaw, practiceRaw)
            let exists = viewContext.safeFetchFirst(fetch) != nil
            if !exists {
                // Create CDWorkModel
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lidString) else { continue }
                let repository = WorkRepository(context: managedObjectContext)
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
        if createdAny { saveCoordinator.save(viewContext, reason: "Adding practice work") }
    }

    private var plannedBanner: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(UIConstants.OpacityConstants.barelyTransparent))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}

#Preview {
    Text("PresentationQuickActionsView preview requires real SwiftData context and cannot run here.")
        .frame(minWidth: 360, minHeight: 240)
        .padding()
}
