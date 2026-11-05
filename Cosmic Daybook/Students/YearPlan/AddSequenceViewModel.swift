import Foundation
import CoreData

@Observable
final class AddSequenceViewModel {
    enum SelectionMode: String, CaseIterable {
        case sequence = "By Group"
        case lesson = "By Lesson"
    }

    var selectionMode: SelectionMode = .sequence
    var selectedLesson: CDLesson?
    var startDate: Date = Date()
    var spacingDays: Int = 3

    // Group picker state
    private(set) var areas: [String] = []
    private var allSequencesByArea: [String: [String]] = [:]
    var selectedArea: String?
    var selectedSequence: String?
    private(set) var allLessonsPresentedInSequence = false

    var availableSequences: [String] {
        guard let area = selectedArea else { return [] }
        return allSequencesByArea[area] ?? []
    }

    private(set) var previewItems: [PreviewItem] = []
    private(set) var showsOverflowWarning = false
    private(set) var overflowCount = 0

    /// Why Schedule All planned nothing, in plain words, for the sheet's
    /// alert. Set only by a refusal (a child who has left the class); the
    /// alert clears it.
    var refusalMessage: String?

    struct PreviewItem: Identifiable {
        let id: UUID
        let lesson: CDLesson
        let lessonName: String
        let area: String
        let date: Date
        let alreadyExists: Bool
        let orderInSequence: Int
    }

    func loadAreasAndSequences(context: NSManagedObjectContext) {
        let req = CDFetchRequest(CDLesson.self)
        let allLessons = context.safeFetch(req)

        var groupsMap: [String: Set<String>] = [:]
        for lesson in allLessons where !lesson.area.isEmpty && !lesson.sequence.isEmpty {
            groupsMap[lesson.area, default: []].insert(lesson.sequence)
        }
        areas = groupsMap.keys.sorted()
        allSequencesByArea = groupsMap.mapValues { $0.sorted() }
    }

    func selectSequence(area: String, sequence: String, student: CDStudent, context: NSManagedObjectContext) {
        guard let studentID = student.id else { return }

        let lessonsInSequence = Self.lessons(area: area, sequence: sequence, in: context)
        guard !lessonsInSequence.isEmpty else {
            selectedLesson = nil
            allLessonsPresentedInSequence = false
            return
        }

        // The first lesson she hasn't had, by the year plan's own rule: a
        // presentation or a mastery mark (the Checklist's Mastered writes
        // only a history row) both count. Reading presented assignments
        // alone started her at lessons she had mastered (bug hunt 2026-11-03 #23).
        let satisfaction = YearPlanSatisfaction.index(forStudents: [studentID.uuidString], in: context)
        if let firstUnpresented = lessonsInSequence.first(where: {
            !Self.isSatisfied($0, for: studentID, by: satisfaction)
        }) {
            allLessonsPresentedInSequence = false
            selectedLesson = firstUnpresented
        } else {
            // She has had every lesson: there is nothing to plan (an entry
            // can't ask for a lesson again; scheduling it is how).
            allLessonsPresentedInSequence = true
            selectedLesson = nil
        }
    }

    private static func isSatisfied(
        _ lesson: CDLesson, for studentID: UUID, by satisfaction: YearPlanSatisfaction
    ) -> Bool {
        guard let lessonID = lesson.id?.uuidString else { return false }
        return satisfaction.isSatisfied(studentID: studentID.uuidString, lessonID: lessonID)
    }

    func computePreview(student: CDStudent, context: NSManagedObjectContext) async {
        guard let lesson = selectedLesson,
              lesson.id != nil,
              let studentID = student.id else {
            clearPreview()
            return
        }
        let studentIDStr = studentID.uuidString

        let allInSequence = Self.lessons(area: lesson.area, sequence: lesson.sequence, in: context)

        // Lessons at or after the selected lesson's orderInSequence that she
        // hasn't had: one already given or mastered gets no entry and takes
        // no day, so the lessons after it aren't pushed back (#23).
        let satisfaction = YearPlanSatisfaction.index(forStudents: [studentIDStr], in: context)
        let sequence = allInSequence.filter {
            $0.orderInSequence >= lesson.orderInSequence
                && !Self.isSatisfied($0, for: studentID, by: satisfaction)
        }
        guard !sequence.isEmpty else {
            clearPreview()
            return
        }

        // Determine school year end for overflow warning
        let cal = AppCalendar.shared
        let schoolYearEnd = Self.schoolYearEnd(after: startDate)

        // Compute dates
        var items: [PreviewItem] = []
        var currentDate = cal.startOfDay(for: startDate)

        // Ensure start date is a school day
        currentDate = YearPlanPacing.schoolDay(onOrAfter: currentDate, in: context)

        for (index, lessonInSequence) in sequence.enumerated() {
            if index > 0 {
                currentDate = YearPlanPacing.advance(
                    from: currentDate, bySchoolDays: Int64(spacingDays), in: context
                )
            }

            let lessonIDStr = lessonInSequence.id?.uuidString ?? ""
            let alreadyExists = !lessonIDStr.isEmpty && plannedEntry(
                lessonID: lessonIDStr, studentID: studentIDStr, context: context
            ) != nil

            items.append(PreviewItem(
                id: lessonInSequence.id ?? UUID(),
                lesson: lessonInSequence,
                lessonName: lessonInSequence.name,
                area: lessonInSequence.area,
                date: currentDate,
                alreadyExists: alreadyExists,
                // The lesson's own place in its sequence, not the preview's
                // count from wherever this run started: two runs numbered
                // from 0 made a drag move the wrong lessons (#24).
                orderInSequence: Int(lessonInSequence.orderInSequence)
            ))
        }

        let overflow = items.filter { $0.date > schoolYearEnd }.count
        showsOverflowWarning = overflow > 0
        overflowCount = overflow
        previewItems = items
    }

    /// Plans every lesson in the preview. Returns false, with
    /// `refusalMessage` set, for a child who has left the class: she gets no
    /// new plans, as she gets no new work (`WorkRepository.requireEnrolled`;
    /// bug hunt 2026-11-03 #32).
    @discardableResult
    func scheduleAll(student: CDStudent, context: NSManagedObjectContext) -> Bool {
        refusalMessage = nil
        guard student.isEnrolled else {
            refusalMessage = Self.notEnrolledMessage(for: student)
            return false
        }
        guard let studentID = student.id,
              let lesson = selectedLesson else { return false }

        let sequenceKey = "\(lesson.area)::\(lesson.sequence)"
        let studentIDStr = studentID.uuidString

        for item in previewItems {
            let lessonIDStr = item.id.uuidString
            // Skip lessons already planned for this student — re-scheduling the
            // same sequence must not create duplicates.
            guard plannedEntry(lessonID: lessonIDStr, studentID: studentIDStr, context: context) == nil else {
                continue
            }

            // A skipped entry is planned again in place, so the lesson keeps one
            // row; only a lesson with no entry at all gets a new one.
            let entry = skippedEntry(lessonID: lessonIDStr, studentID: studentIDStr, context: context)
                ?? CDYearPlanEntry(context: context)
            entry.studentID = studentIDStr
            entry.lessonID = lessonIDStr
            entry.promotedAssignmentID = nil
            entry.plannedDate = item.date
            entry.spacingSchoolDays = Int64(spacingDays)
            entry.sequenceGroupKey = sequenceKey
            entry.orderInSequence = Int64(item.orderInSequence)
            entry.status = .planned
        }

        context.safeSave()
        return true
    }

    /// The sentence a child who has left the class gets instead of new plans.
    static func notEnrolledMessage(for student: CDStudent) -> String {
        "\(student.shortName) has left the class, so they can't get new plans."
    }

    // MARK: - Helpers

    /// Every lesson in one area and sequence, in their order.
    private static func lessons(
        area: String, sequence: String, in context: NSManagedObjectContext
    ) -> [CDLesson] {
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(format: "area ==[c] %@ AND sequence ==[c] %@", area, sequence)
        req.sortDescriptors = [NSSortDescriptor(key: "orderInSequence", ascending: true)]
        return context.safeFetch(req)
    }

    private func clearPreview() {
        previewItems = []
        showsOverflowWarning = false
        overflowCount = 0
    }

    /// June 30 of the school year `startDate` falls in, for the overflow warning.
    private static func schoolYearEnd(after startDate: Date) -> Date {
        let cal = AppCalendar.shared
        let year = cal.component(.year, from: startDate)
        let month = cal.component(.month, from: startDate)
        var endComps = DateComponents()
        endComps.year = month >= 8 ? year + 1 : year
        endComps.month = 6
        endComps.day = 30
        return cal.date(from: endComps) ?? Date.distantFuture
    }

    /// The Year Plan entry already planning this lesson for this student
    /// (planned or promoted), if any. Uses the same uniqueness key (lessonID +
    /// studentID) as the rest of the Year Plan services, so the preview and the
    /// insert agree. A skipped entry doesn't count: skipping is the guide's
    /// "not this year", and counting it left those lessons out of a re-added
    /// sequence with gaps in the dates (2026-10-11 hunt, #36).
    private func plannedEntry(
        lessonID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) -> CDYearPlanEntry? {
        entries(lessonID: lessonID, studentID: studentID, context: context).first { $0.status != .skipped }
    }

    /// A skipped entry for this lesson and student, to plan again in place.
    private func skippedEntry(
        lessonID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) -> CDYearPlanEntry? {
        entries(lessonID: lessonID, studentID: studentID, context: context).first { $0.status == .skipped }
    }

    private func entries(
        lessonID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let req = CDFetchRequest(CDYearPlanEntry.self)
        req.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID == %@",
            lessonID, studentID
        )
        return context.safeFetch(req)
    }
}
