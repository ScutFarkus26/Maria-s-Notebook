import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the scoped reads behind the presentation detail and the
/// "school days since last lesson" row against the whole-table reads they replaced.
@MainActor
struct PresentationDetailScopedReadsTests {

    // MARK: - Mastery state

    private func legacyProficiency(
        lessonID: String, studentIDs: [String], context: NSManagedObjectContext
    ) throws -> LessonPresentationState {
        let all = try context.fetch(CDFetchRequest(CDLessonPresentation.self))
        let matching = all.filter { $0.lessonID == lessonID && studentIDs.contains($0.studentID) }
        if matching.contains(where: { $0.state == .proficient }) { return .proficient }
        if matching.contains(where: { $0.state == .readyForAssessment }) { return .readyForAssessment }
        if matching.contains(where: { $0.state == .practicing }) { return .practicing }
        return .presented
    }

    @Test func proficiencyMatchesWholeTableFilter() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let lessons = (0..<4).map { _ in UUID().uuidString }
        let students = (0..<4).map { _ in UUID().uuidString }
        let states: [LessonPresentationState] = [.presented, .practicing, .readyForAssessment, .proficient]
        // Lesson i's rows climb to states[i] and student j's row sits at
        // states[min(i, j)], so different lessons and groups have different highs.
        for (i, lesson) in lessons.enumerated() {
            for (j, student) in students.enumerated() where j != 1 || i != 2 {
                let lp = CDLessonPresentation(context: context)
                lp.lessonID = lesson
                lp.studentID = student
                lp.state = states[min(i, j)]
            }
        }
        try context.save()

        var seen: Set<String> = []
        for lesson in lessons {
            for take in 1...students.count {
                for offset in 0..<students.count {
                    let group = Array((students + students)[offset..<(offset + take)])
                    let scoped = PresentationDetailViewModel.loadProficiencyState(
                        lessonID: lesson, studentIDs: group, viewContext: context
                    )
                    let legacy = try legacyProficiency(lessonID: lesson, studentIDs: group, context: context)
                    #expect(scoped == legacy)
                    seen.insert(scoped.rawValue)
                }
            }
        }
        #expect(seen.count == 4)

        let request = PresentationDetailViewModel.presentationsRequest(lessonID: lessons[0], studentIDs: students)
        let scopedRows = Set(try context.fetch(request).map(\.objectID))
        let legacyRows = Set(try context.fetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.lessonID == lessons[0] && students.contains($0.studentID) }
            .map(\.objectID))
        #expect(scopedRows == legacyRows)
        #expect(!scopedRows.isEmpty)
    }

    // MARK: - Days since last lesson

    /// The view's calculation before 2026-09-22: every presented row, filtered and maxed.
    private func legacyLastLessonDate(studentID: UUID, context: NSManagedObjectContext) throws -> Date? {
        let parsha = CDFetchRequest(CDLesson.self)
        parsha.predicate = NSPredicate(format: "area ==[c] 'parsha' OR sequence ==[c] 'parsha'")
        let excluded = Set(try context.fetch(parsha).compactMap(\.id))
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "presentedAt != nil")
        var latest: Date?
        for la in try context.fetch(request)
        where la.studentIDs.contains(studentID.uuidString) && !excluded.contains(la.resolvedLessonID) {
            guard let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt else { continue }
            if latest.map({ when > $0 }) ?? true { latest = when }
        }
        return latest
    }

    @Test func lastLessonDateMatchesWholeTableScan() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let parshaLesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bereshit", area: "Parsha", sequence: "Genesis"
        )
        let parshaSeq = CoreDataTestHelpers.seedLesson(in: context, name: "Noach", area: "Hebrew", sequence: "PARSHA")
        let math = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        let studentIDs = (0..<4).map { _ in UUID() }
        let base = 1_780_000_000.0

        func presentation(_ lesson: CDLesson, _ students: [UUID], day: Double) {
            let la = CDLessonAssignment(context: context)
            la.lessonID = lesson.id?.uuidString ?? ""
            la.studentIDs = students.map(\.uuidString)
            la.markPresented(at: Date(timeIntervalSince1970: base + day * 86_400))
        }
        presentation(math, [studentIDs[0], studentIDs[1]], day: 1)
        presentation(math, [studentIDs[0]], day: 5)
        presentation(parshaLesson, [studentIDs[0], studentIDs[2]], day: 9)   // newer, but parsha
        presentation(parshaSeq, [studentIDs[1]], day: 7)                     // parsha by sequence
        presentation(math, [studentIDs[2]], day: 3)
        // Only parsha for student 3, and a scheduled (not presented) row.
        presentation(parshaLesson, [studentIDs[3]], day: 2)
        let scheduled = CDLessonAssignment(context: context)
        scheduled.lessonID = math.id?.uuidString ?? ""
        scheduled.studentIDs = [studentIDs[3].uuidString]
        scheduled.schedule(onDay: Date(timeIntervalSince1970: base + 20 * 86_400))
        try context.save()
        // An unsaved newer presentation must be seen too.
        presentation(math, [studentIDs[1]], day: 6)

        for studentID in studentIDs {
            let scoped = DaysSinceLastLessonView.lastLessonDate(studentID: studentID, in: context)
            let legacy = try legacyLastLessonDate(studentID: studentID, context: context)
            #expect(scoped == legacy)
        }
        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: studentIDs[0], in: context)
                == Date(timeIntervalSince1970: base + 5 * 86_400))
        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: studentIDs[1], in: context)
                == Date(timeIntervalSince1970: base + 6 * 86_400))
        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: studentIDs[3], in: context) == nil)
    }
}
