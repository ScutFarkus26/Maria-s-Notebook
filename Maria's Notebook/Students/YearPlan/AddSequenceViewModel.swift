import Foundation
import CoreData

@Observable
@MainActor
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

        // Fetch all lessons in area+sequence sorted by order
        let lessonReq = CDFetchRequest(CDLesson.self)
        lessonReq.predicate = NSPredicate(
            format: "area ==[c] %@ AND sequence ==[c] %@",
            area, sequence
        )
        lessonReq.sortDescriptors = [NSSortDescriptor(key: "orderInSequence", ascending: true)]
        let lessonsInSequence = context.safeFetch(lessonReq)
        guard !lessonsInSequence.isEmpty else {
            selectedLesson = nil
            allLessonsPresentedInSequence = false
            return
        }

        // Fetch presented assignments
        let assignmentReq = CDFetchRequest(CDLessonAssignment.self)
        assignmentReq.predicate = NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
        let presentedAssignments = context.safeFetch(assignmentReq)

        // Build set of lesson IDs this student has been presented
        let lessonIDsInSequence = Set(lessonsInSequence.compactMap { $0.id?.uuidString })
        var presentedLessonIDs = Set<String>()
        for assignment in presentedAssignments {
            guard lessonIDsInSequence.contains(assignment.lessonID) else { continue }
            if assignment.studentUUIDs.contains(studentID) {
                presentedLessonIDs.insert(assignment.lessonID)
            }
        }

        // Find first unpresented lesson
        if let firstUnpresented = lessonsInSequence.first(where: {
            guard let id = $0.id?.uuidString else { return false }
            return !presentedLessonIDs.contains(id)
        }) {
            allLessonsPresentedInSequence = false
            selectedLesson = firstUnpresented
        } else {
            // All presented — default to first lesson for re-scheduling
            allLessonsPresentedInSequence = true
            selectedLesson = lessonsInSequence.first
        }
    }

    func computePreview(student: CDStudent, context: NSManagedObjectContext) async {
        guard let lesson = selectedLesson,
              lesson.id != nil,
              let studentID = student.id else {
            previewItems = []
            showsOverflowWarning = false
            overflowCount = 0
            return
        }
        let studentIDStr = studentID.uuidString

        // Fetch all lessons in the same area + sequence
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(
            format: "area ==[c] %@ AND sequence ==[c] %@",
            lesson.area, lesson.sequence
        )
        req.sortDescriptors = [NSSortDescriptor(key: "orderInSequence", ascending: true)]
        let allInSequence = context.safeFetch(req)

        // Filter to lessons at or after the selected lesson's orderInSequence
        let sequence = allInSequence.filter { $0.orderInSequence >= lesson.orderInSequence }
        guard !sequence.isEmpty else {
            previewItems = []
            showsOverflowWarning = false
            overflowCount = 0
            return
        }

        // Determine school year end for overflow warning
        let cal = AppCalendar.shared
        let year = cal.component(.year, from: startDate)
        let month = cal.component(.month, from: startDate)
        let endYear = month >= 8 ? year + 1 : year
        var endComps = DateComponents()
        endComps.year = endYear
        endComps.month = 6
        endComps.day = 30
        let schoolYearEnd = cal.date(from: endComps) ?? Date.distantFuture

        // Compute dates
        var items: [PreviewItem] = []
        var currentDate = cal.startOfDay(for: startDate)

        // Ensure start date is a school day
        if await SchoolCalendar.isNonSchoolDay(currentDate, using: context) {
            currentDate = await SchoolCalendar.nextSchoolDay(after: currentDate, using: context)
        }

        for (index, lessonInSequence) in sequence.enumerated() {
            if index > 0 {
                for _ in 0..<spacingDays {
                    currentDate = await SchoolCalendar.nextSchoolDay(after: currentDate, using: context)
                }
            }

            let lessonIDStr = lessonInSequence.id?.uuidString ?? ""
            let alreadyExists = !lessonIDStr.isEmpty && entryExists(
                lessonID: lessonIDStr, studentID: studentIDStr, context: context
            )

            items.append(PreviewItem(
                id: lessonInSequence.id ?? UUID(),
                lesson: lessonInSequence,
                lessonName: lessonInSequence.name,
                area: lessonInSequence.area,
                date: currentDate,
                alreadyExists: alreadyExists,
                orderInSequence: index
            ))
        }

        let overflow = items.filter { $0.date > schoolYearEnd }.count
        showsOverflowWarning = overflow > 0
        overflowCount = overflow
        previewItems = items
    }

    func scheduleAll(student: CDStudent, context: NSManagedObjectContext) {
        guard let studentID = student.id,
              let lesson = selectedLesson else { return }

        let sequenceKey = "\(lesson.area)::\(lesson.sequence)"
        let studentIDStr = studentID.uuidString

        for item in previewItems {
            let lessonIDStr = item.id.uuidString
            // Skip lessons that already have a Year Plan entry for this student —
            // re-scheduling the same sequence must not create duplicates.
            guard !entryExists(lessonID: lessonIDStr, studentID: studentIDStr, context: context) else {
                continue
            }

            let entry = CDYearPlanEntry(context: context)
            entry.studentID = studentIDStr
            entry.lessonID = lessonIDStr
            entry.plannedDate = item.date
            entry.spacingSchoolDays = Int64(spacingDays)
            entry.sequenceGroupKey = sequenceKey
            entry.orderInSequence = Int64(item.orderInSequence)
            entry.status = .planned
        }

        context.safeSave()
    }

    // MARK: - Helpers

    /// Whether a Year Plan entry already exists for this lesson + student.
    /// Uses the same uniqueness key (lessonID + studentID) as the preview and the
    /// rest of the Year Plan services, so the preview and the insert agree.
    private func entryExists(
        lessonID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) -> Bool {
        let req = CDFetchRequest(CDYearPlanEntry.self)
        req.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID == %@",
            lessonID, studentID
        )
        req.fetchLimit = 1
        return context.safeFetchFirst(req) != nil
    }
}
