import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Progress Dashboard and the student page's track timeline climb the Checklist's
/// ladder (`ChecklistDisplayStatus.resolve`): closed work is not mastery, so a lesson whose
/// work is all closed reads Reviewing until it carries a mastery mark. Until 2026-10-10 both
/// called it "Mastered" as soon as every work row closed, while the Checklist said Reviewing.
@Suite("Lesson mastery status")
@MainActor
struct LessonMasteryStatusTests {

    @Test(
        "Closed work without a mastery mark is Reviewing, whatever it closed as",
        arguments: WorkStatus.allCases.filter(\.isClosed)
    )
    func closedWorkIsNotMastery(closedAs: WorkStatus) {
        let status = LessonNodeStatus.resolve(
            isPresented: true, scheduledFor: nil, isMastered: false, workStatuses: [closedAs]
        )
        #expect(status == .reviewing)
        #expect(ChecklistDisplayStatus.resolve(
            isMastered: false, workStatuses: [closedAs], isPresented: true, isPlanned: false
        ) == .reviewing)
    }

    @Test("A mastery mark is Mastered, with or without work")
    func markIsMastered() {
        for work in [[], [WorkStatus.active], [.review], [.done]] {
            #expect(LessonNodeStatus.resolve(
                isPresented: true, scheduledFor: nil, isMastered: true, workStatuses: work
            ) == .mastered)
        }
    }

    @Test("The timeline status names the same rung as the Checklist's cell")
    func timelineMatchesChecklist() {
        let plannedDay = Date(timeIntervalSince1970: 1_790_000_000)
        let work: [[WorkStatus]] = [[], [.active], [.review], [.done], [.active, .done], [.review, .mastered]]
        for isMastered in [false, true] {
            for isPresented in [false, true] {
                for scheduledFor in [nil, plannedDay] {
                    for statuses in work {
                        let node = LessonNodeStatus.resolve(
                            isPresented: isPresented, scheduledFor: scheduledFor,
                            isMastered: isMastered, workStatuses: statuses
                        )
                        let cell = ChecklistDisplayStatus.resolve(
                            isMastered: isMastered, workStatuses: statuses,
                            isPresented: isPresented, isPlanned: scheduledFor != nil
                        )
                        // Same rung: same words, except the two below Presented, which the
                        // timeline words its own way (and only a dated plan is Scheduled).
                        switch cell {
                        case .planned: #expect(node == .scheduled(plannedDay))
                        case .ready, .notReady: #expect(node == .notStarted)
                        default: #expect(node.label == cell.label, "\(node) vs \(cell)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - The screens

    private struct Seeded {
        let context: NSManagedObjectContext
        let student: CDStudent
        let lesson: CDLesson
    }

    /// One child, one presented lesson on "Math — Counting", and her work on it closed as
    /// Mastered (a work verdict, not a mastery mark).
    private func seedClosedWork() throws -> Seeded {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Counting Chains")
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)

        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lessonID.uuidString
        assignment.studentIDs = [studentID.uuidString]
        assignment.state = .presented
        assignment.presentedAt = Date()

        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: studentID, lessonID: lessonID)
        work.status = .mastered
        #expect(CoreDataTestHelpers.save(context))
        return Seeded(context: context, student: student, lesson: lesson)
    }

    private func addMark(_ seeded: Seeded) throws {
        let mark = CDLessonPresentation(context: seeded.context)
        mark.studentID = try #require(seeded.student.id).uuidString
        mark.lessonID = try #require(seeded.lesson.id).uuidString
        mark.state = .proficient
        #expect(CoreDataTestHelpers.save(seeded.context))
    }

    private func dashboardStatus(_ seeded: Seeded) throws -> LessonNodeStatus {
        let dashboard = ProgressDashboardViewModel()
        dashboard.loadData(context: seeded.context)
        let pill = try #require(dashboard.studentCards.first?.subjects.first?.sequences.first?.pills.first)
        return pill.status
    }

    @Test("The Progress Dashboard waits for the mastery mark")
    func dashboardWaitsForMark() throws {
        let seeded = try seedClosedWork()
        #expect(try dashboardStatus(seeded) == .reviewing)
        try addMark(seeded)
        #expect(try dashboardStatus(seeded) == .mastered)
    }

    @Test("The track timeline waits for the mastery mark, and counts only marks")
    func timelineWaitsForMark() throws {
        let seeded = try seedClosedWork()
        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Counting", context: seeded.context)
        #expect(timeline.nodes.first?.status == .reviewing)
        #expect(timeline.completedCount == 0)

        try addMark(seeded)
        timeline.configure(for: seeded.student, area: "Math", sequence: "Counting", context: seeded.context)
        #expect(timeline.nodes.first?.status == .mastered)
        #expect(timeline.completedCount == 1)
    }
}
