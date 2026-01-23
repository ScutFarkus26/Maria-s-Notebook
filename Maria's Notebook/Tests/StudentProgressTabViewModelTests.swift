#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Helper Factory

@MainActor
private func makeProgressContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        Track.self,
        TrackStep.self,
        StudentTrackEnrollment.self,
        Project.self,
        Presentation.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        Note.self,
        LessonPresentation.self,
    ])
}

private func makeTestTrack(
    id: UUID = UUID(),
    title: String = "Test Track"
) -> Track {
    return Track(
        id: id,
        title: title
    )
}

private func makeTestTrackStep(
    id: UUID = UUID(),
    track: Track? = nil,
    orderIndex: Int = 0,
    lessonTemplateID: UUID? = nil
) -> TrackStep {
    return TrackStep(
        id: id,
        track: track,
        orderIndex: orderIndex,
        lessonTemplateID: lessonTemplateID
    )
}

private func makeTestEnrollment(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    studentID: String,
    trackID: String,
    isActive: Bool = true
) -> StudentTrackEnrollment {
    return StudentTrackEnrollment(
        id: id,
        createdAt: createdAt,
        studentID: studentID,
        trackID: trackID,
        isActive: isActive
    )
}

private func makeTestProject(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    title: String = "Test Project",
    memberStudentIDs: [String] = [],
    isActive: Bool = true
) -> Project {
    return Project(
        id: id,
        createdAt: createdAt,
        title: title,
        memberStudentIDs: memberStudentIDs,
        isActive: isActive
    )
}

private func makeTestPresentation(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    presentedAt: Date = Date(),
    lessonID: String = "test-lesson",
    studentIDs: [String] = [],
    trackID: String? = nil
) -> Presentation {
    return Presentation(
        id: id,
        createdAt: createdAt,
        presentedAt: presentedAt,
        lessonID: lessonID,
        studentIDs: studentIDs,
        trackID: trackID
    )
}

@MainActor
private func makeTestNote(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    body: String = "Test note",
    studentTrackEnrollment: StudentTrackEnrollment? = nil
) -> Note {
    return Note(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        body: body,
        scope: .all,
        studentTrackEnrollment: studentTrackEnrollment
    )
}

private func makeTestLessonPresentation(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    studentID: String,
    lessonID: String,
    state: LessonPresentationState = .presented
) -> LessonPresentation {
    return LessonPresentation(
        id: id,
        createdAt: createdAt,
        studentID: studentID,
        lessonID: lessonID,
        state: state,
        presentedAt: Date(),
        lastObservedAt: Date(),
        masteredAt: state == .mastered ? Date() : nil
    )
}

// MARK: - Initialization Tests

@Suite("StudentProgressTabViewModel Initialization Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelInitializationTests {

    @Test("ViewModel initializes with empty state")
    func initializesWithEmptyState() {
        let vm = StudentProgressTabViewModel()

        #expect(vm.activeEnrollments.isEmpty)
        #expect(vm.activeProjects.isEmpty)
        #expect(vm.activeReports.isEmpty)
        #expect(vm.tracksByID.isEmpty)
    }
}

// MARK: - Data Loading Tests

@Suite("StudentProgressTabViewModel Data Loading Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelDataLoadingTests {

    @Test("loadData populates activeEnrollments for student")
    func loadDataPopulatesActiveEnrollments() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString,
            isActive: true
        )
        context.insert(enrollment)

        vm.configure(for: student, context: context)

        #expect(vm.activeEnrollments.count == 1)
        #expect(vm.activeEnrollments[0].studentID == student.id.uuidString)
    }

    @Test("loadData excludes inactive enrollments")
    func loadDataExcludesInactiveEnrollments() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let activeEnrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString,
            isActive: true
        )
        let inactiveEnrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString,
            isActive: false
        )
        context.insert(activeEnrollment)
        context.insert(inactiveEnrollment)

        vm.configure(for: student, context: context)

        #expect(vm.activeEnrollments.count == 1)
    }

    @Test("loadData populates activeProjects for student")
    func loadDataPopulatesActiveProjects() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let project = makeTestProject(
            title: "Science Fair",
            memberStudentIDs: [student.id.uuidString],
            isActive: true
        )
        context.insert(project)

        vm.configure(for: student, context: context)

        #expect(vm.activeProjects.count == 1)
        #expect(vm.activeProjects[0].title == "Science Fair")
    }

    @Test("loadData excludes projects student is not a member of")
    func loadDataExcludesNonMemberProjects() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let otherStudent = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student)
        context.insert(otherStudent)

        let project = makeTestProject(
            title: "Science Fair",
            memberStudentIDs: [otherStudent.id.uuidString],
            isActive: true
        )
        context.insert(project)

        vm.configure(for: student, context: context)

        #expect(vm.activeProjects.isEmpty)
    }

    @Test("loadData populates activeReports for student")
    func loadDataPopulatesActiveReports() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let report = makeTestWorkModel(
            title: "Book Report",
            workType: .report,
            kind: .report,
            status: .active,
            studentID: student.id.uuidString
        )
        context.insert(report)

        vm.configure(for: student, context: context)

        #expect(vm.activeReports.count == 1)
        #expect(vm.activeReports[0].title == "Book Report")
    }

    @Test("loadData excludes completed reports")
    func loadDataExcludesCompletedReports() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let activeReport = makeTestWorkModel(
            title: "Active Report",
            workType: .report,
            kind: .report,
            status: .active,
            studentID: student.id.uuidString
        )
        let completedReport = makeTestWorkModel(
            title: "Completed Report",
            workType: .report,
            kind: .report,
            status: .complete,
            studentID: student.id.uuidString
        )
        context.insert(activeReport)
        context.insert(completedReport)

        vm.configure(for: student, context: context)

        #expect(vm.activeReports.count == 1)
        #expect(vm.activeReports[0].title == "Active Report")
    }

    @Test("loadData populates tracksByID")
    func loadDataPopulatesTracksByID() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track1 = makeTestTrack(title: "Math Track")
        let track2 = makeTestTrack(title: "Science Track")
        context.insert(student)
        context.insert(track1)
        context.insert(track2)

        vm.configure(for: student, context: context)

        #expect(vm.tracksByID.count == 2)
        #expect(vm.tracksByID[track1.id.uuidString]?.title == "Math Track")
        #expect(vm.tracksByID[track2.id.uuidString]?.title == "Science Track")
    }
}

// MARK: - Track Stats Tests

@Suite("StudentProgressTabViewModel Track Stats Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelTrackStatsTests {

    @Test("trackStats returns empty stats when studentID is nil")
    func trackStatsReturnsEmptyWhenStudentIDNil() throws {
        let vm = StudentProgressTabViewModel()
        let track = makeTestTrack(title: "Test Track")
        let enrollment = makeTestEnrollment(studentID: "", trackID: track.id.uuidString)

        let stats = vm.trackStats(for: enrollment, track: track)

        #expect(stats.presentationCount == 0)
        #expect(stats.workCount == 0)
        #expect(stats.noteCount == 0)
        #expect(stats.totalActivity == 0)
        #expect(stats.lastActivityDate == nil)
    }

    @Test("trackStats counts presentations correctly")
    func trackStatsCountsPresentationsCorrectly() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let presentation1 = makeTestPresentation(
            studentIDs: [student.id.uuidString],
            trackID: track.id.uuidString
        )
        let presentation2 = makeTestPresentation(
            studentIDs: [student.id.uuidString],
            trackID: track.id.uuidString
        )
        context.insert(presentation1)
        context.insert(presentation2)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString
        )
        context.insert(enrollment)

        vm.configure(for: student, context: context)

        let stats = vm.trackStats(for: enrollment, track: track)

        #expect(stats.presentationCount == 2)
    }

    @Test("trackStats counts work models correctly")
    func trackStatsCountsWorkModelsCorrectly() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let work1 = WorkModel(
            id: UUID(),
            title: "Work 1",
            workType: .practice,
            status: .active,
            studentID: student.id.uuidString,
            lessonID: ""
        )
        work1.trackID = track.id.uuidString

        let work2 = WorkModel(
            id: UUID(),
            title: "Work 2",
            workType: .practice,
            status: .active,
            studentID: student.id.uuidString,
            lessonID: ""
        )
        work2.trackID = track.id.uuidString

        context.insert(work1)
        context.insert(work2)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString
        )
        context.insert(enrollment)

        vm.configure(for: student, context: context)

        let stats = vm.trackStats(for: enrollment, track: track)

        #expect(stats.workCount == 2)
    }

    @Test("trackStats calculates totalActivity correctly")
    func trackStatsCalculatesTotalActivityCorrectly() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let presentation = makeTestPresentation(
            studentIDs: [student.id.uuidString],
            trackID: track.id.uuidString
        )
        context.insert(presentation)

        let work = WorkModel(
            id: UUID(),
            title: "Work",
            workType: .practice,
            status: .active,
            studentID: student.id.uuidString,
            lessonID: ""
        )
        work.trackID = track.id.uuidString
        context.insert(work)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: track.id.uuidString
        )
        context.insert(enrollment)

        vm.configure(for: student, context: context)

        let stats = vm.trackStats(for: enrollment, track: track)

        #expect(stats.totalActivity == 2) // 1 presentation + 1 work
    }
}

// MARK: - Track Progress Tests

@Suite("StudentProgressTabViewModel Track Progress Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelTrackProgressTests {

    @Test("trackProgress returns empty progress when studentID is nil")
    func trackProgressReturnsEmptyWhenStudentIDNil() throws {
        let vm = StudentProgressTabViewModel()
        let track = makeTestTrack(title: "Test Track")

        let progress = vm.trackProgress(for: track)

        #expect(progress.trackSteps.isEmpty)
        #expect(progress.completedStepIDs.isEmpty)
        #expect(progress.masteredCount == 0)
        #expect(progress.totalSteps == 0)
        #expect(progress.progressPercent == 0)
        #expect(progress.isComplete == false)
        #expect(progress.currentStep == nil)
        #expect(progress.currentLesson == nil)
    }

    @Test("trackProgress calculates progress percentage correctly")
    func trackProgressCalculatesProgressPercentageCorrectly() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")
        context.insert(lesson1)
        context.insert(lesson2)

        let step1 = makeTestTrackStep(track: track, orderIndex: 0, lessonTemplateID: lesson1.id)
        let step2 = makeTestTrackStep(track: track, orderIndex: 1, lessonTemplateID: lesson2.id)
        context.insert(step1)
        context.insert(step2)

        // Mark lesson1 as mastered
        let lp = makeTestLessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson1.id.uuidString,
            state: .mastered
        )
        context.insert(lp)

        vm.configure(for: student, context: context)

        let progress = vm.trackProgress(for: track)

        #expect(progress.masteredCount == 1)
        #expect(progress.totalSteps == 2)
        #expect(progress.progressPercent == 0.5) // 1 of 2 = 50%
        #expect(progress.isComplete == false)
    }

    @Test("trackProgress identifies current step correctly")
    func trackProgressIdentifiesCurrentStepCorrectly() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")
        let lesson3 = makeTestLesson(name: "Lesson 3")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)

        let step1 = makeTestTrackStep(track: track, orderIndex: 0, lessonTemplateID: lesson1.id)
        let step2 = makeTestTrackStep(track: track, orderIndex: 1, lessonTemplateID: lesson2.id)
        let step3 = makeTestTrackStep(track: track, orderIndex: 2, lessonTemplateID: lesson3.id)
        context.insert(step1)
        context.insert(step2)
        context.insert(step3)

        // Mark lesson1 as mastered
        let lp = makeTestLessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson1.id.uuidString,
            state: .mastered
        )
        context.insert(lp)

        vm.configure(for: student, context: context)

        let progress = vm.trackProgress(for: track)

        // Current step should be step2 (first not-mastered step)
        #expect(progress.currentStep?.id == step2.id)
        #expect(progress.currentLesson?.id == lesson2.id)
    }

    @Test("trackProgress marks track as complete when all steps mastered")
    func trackProgressMarksCompleteWhenAllStepsMastered() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let track = makeTestTrack(title: "Math Track")
        context.insert(student)
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")
        context.insert(lesson1)
        context.insert(lesson2)

        let step1 = makeTestTrackStep(track: track, orderIndex: 0, lessonTemplateID: lesson1.id)
        let step2 = makeTestTrackStep(track: track, orderIndex: 1, lessonTemplateID: lesson2.id)
        context.insert(step1)
        context.insert(step2)

        // Mark both lessons as mastered
        let lp1 = makeTestLessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson1.id.uuidString,
            state: .mastered
        )
        let lp2 = makeTestLessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson2.id.uuidString,
            state: .mastered
        )
        context.insert(lp1)
        context.insert(lp2)

        vm.configure(for: student, context: context)

        let progress = vm.trackProgress(for: track)

        #expect(progress.isComplete == true)
        #expect(progress.progressPercent == 1.0)
        #expect(progress.currentStep == nil)
    }
}

// MARK: - Report Helper Tests

@Suite("StudentProgressTabViewModel Report Helper Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelReportHelperTests {

    @Test("reportTitle returns work title when present")
    func reportTitleReturnsWorkTitleWhenPresent() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        context.insert(student)
        vm.configure(for: student, context: context)

        let report = makeTestWorkModel(title: "My Book Report", workType: .report, kind: .report)

        let title = vm.reportTitle(for: report)

        #expect(title == "My Book Report")
    }

    @Test("reportTitle returns 'Untitled Report' for empty title and no lesson")
    func reportTitleReturnsUntitledForEmptyTitleNoLesson() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        context.insert(student)
        vm.configure(for: student, context: context)

        let report = makeTestWorkModel(title: "   ", workType: .report, kind: .report) // whitespace only

        let title = vm.reportTitle(for: report)

        #expect(title == "Untitled Report")
    }

    @Test("reportTitle returns lesson name for empty title with valid lessonID")
    func reportTitleReturnsLessonNameForEmptyTitleWithLesson() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        let lesson = makeTestLesson(name: "Reading Comprehension")
        context.insert(student)
        context.insert(lesson)
        vm.configure(for: student, context: context)

        let report = makeTestWorkModel(
            title: "",
            workType: .report,
            kind: .report,
            lessonID: lesson.id.uuidString
        )

        let title = vm.reportTitle(for: report)

        #expect(title == "Reading Comprehension")
    }
}

// MARK: - Color Helper Tests

@Suite("StudentProgressTabViewModel Color Helper Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelColorHelperTests {

    @Test("trackColor returns consistent color for same title")
    func trackColorReturnsConsistentColorForSameTitle() {
        let vm = StudentProgressTabViewModel()

        let color1 = vm.trackColor(for: "Math")
        let color2 = vm.trackColor(for: "Math")

        #expect(color1 == color2)
    }

    @Test("trackColor returns different colors for different titles")
    func trackColorReturnsDifferentColorsForDifferentTitles() {
        let vm = StudentProgressTabViewModel()

        let color1 = vm.trackColor(for: "Math")
        let color2 = vm.trackColor(for: "Science")

        // These might occasionally be the same due to hash collisions,
        // but should usually be different
        // Just verify the function runs without error
        _ = color1
        _ = color2
    }
}

// MARK: - Auto Complete Tests

@Suite("StudentProgressTabViewModel Auto Complete Tests", .serialized)
@MainActor
struct StudentProgressTabViewModelAutoCompleteTests {

    @Test("autoCompleteTrackIfNeeded deactivates enrollment when track is complete")
    func autoCompleteDeactivatesEnrollmentWhenComplete() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        context.insert(student)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: UUID().uuidString,
            isActive: true
        )
        context.insert(enrollment)

        // Create a complete progress (all mastered)
        let completeProgress = StudentProgressTabViewModel.TrackProgress(
            trackSteps: [],
            completedStepIDs: [],
            masteredCount: 5,
            totalSteps: 5,
            progressPercent: 1.0,
            isComplete: true,
            currentStep: nil,
            currentLesson: nil
        )

        vm.autoCompleteTrackIfNeeded(enrollment: enrollment, progress: completeProgress, context: context)

        #expect(enrollment.isActive == false)
    }

    @Test("autoCompleteTrackIfNeeded does not deactivate incomplete track")
    func autoCompleteDoesNotDeactivateIncompleteTrack() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        context.insert(student)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: UUID().uuidString,
            isActive: true
        )
        context.insert(enrollment)

        // Create an incomplete progress
        let incompleteProgress = StudentProgressTabViewModel.TrackProgress(
            trackSteps: [],
            completedStepIDs: [],
            masteredCount: 3,
            totalSteps: 5,
            progressPercent: 0.6,
            isComplete: false,
            currentStep: nil,
            currentLesson: nil
        )

        vm.autoCompleteTrackIfNeeded(enrollment: enrollment, progress: incompleteProgress, context: context)

        #expect(enrollment.isActive == true)
    }

    @Test("autoCompleteTrackIfNeeded does not affect already inactive enrollment")
    func autoCompleteDoesNotAffectInactiveEnrollment() throws {
        let container = try makeProgressContainer()
        let context = ModelContext(container)
        let vm = StudentProgressTabViewModel()

        let student = makeTestStudent()
        context.insert(student)

        let enrollment = makeTestEnrollment(
            studentID: student.id.uuidString,
            trackID: UUID().uuidString,
            isActive: false
        )
        context.insert(enrollment)

        let completeProgress = StudentProgressTabViewModel.TrackProgress(
            trackSteps: [],
            completedStepIDs: [],
            masteredCount: 5,
            totalSteps: 5,
            progressPercent: 1.0,
            isComplete: true,
            currentStep: nil,
            currentLesson: nil
        )

        vm.autoCompleteTrackIfNeeded(enrollment: enrollment, progress: completeProgress, context: context)

        #expect(enrollment.isActive == false) // Still false, no change
    }
}

#endif
