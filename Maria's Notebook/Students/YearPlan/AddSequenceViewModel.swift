import Foundation
import CoreData

@Observable
@MainActor
final class AddSequenceViewModel {
    enum SelectionMode: String, CaseIterable {
        case group = "By Group"
        case lesson = "By Lesson"
    }

    var selectionMode: SelectionMode = .group
    var selectedLesson: CDLesson?
    var startDate: Date = Date()
    var spacingDays: Int = 3

    // Group picker state
    private(set) var subjects: [String] = []
    private var allGroupsBySubject: [String: [String]] = [:]
    var selectedSubject: String?
    var selectedGroup: String?
    private(set) var allLessonsPresentedInGroup = false

    var availableGroups: [String] {
        guard let subject = selectedSubject else { return [] }
        return allGroupsBySubject[subject] ?? []
    }

    private(set) var previewItems: [PreviewItem] = []
    private(set) var showsOverflowWarning = false
    private(set) var overflowCount = 0

    struct PreviewItem: Identifiable {
        let id: UUID
        let lesson: CDLesson
        let lessonName: String
        let subject: String
        let date: Date
        let alreadyExists: Bool
        let orderInSequence: Int
    }

    func loadSubjectsAndGroups(context: NSManagedObjectContext) {
        let req = CDFetchRequest(CDLesson.self)
        let allLessons = context.safeFetch(req)

        var groupsMap: [String: Set<String>] = [:]
        for lesson in allLessons where !lesson.subject.isEmpty && !lesson.group.isEmpty {
            groupsMap[lesson.subject, default: []].insert(lesson.group)
        }
        subjects = groupsMap.keys.sorted()
        allGroupsBySubject = groupsMap.mapValues { $0.sorted() }
    }

    func selectGroup(subject: String, group: String, student: CDStudent, context: NSManagedObjectContext) {
        guard let studentID = student.id else { return }

        // Fetch all lessons in subject+group sorted by order
        let lessonReq = CDFetchRequest(CDLesson.self)
        lessonReq.predicate = NSPredicate(
            format: "subject ==[c] %@ AND group ==[c] %@",
            subject, group
        )
        lessonReq.sortDescriptors = [NSSortDescriptor(key: "orderInGroup", ascending: true)]
        let lessonsInGroup = context.safeFetch(lessonReq)
        guard !lessonsInGroup.isEmpty else {
            selectedLesson = nil
            allLessonsPresentedInGroup = false
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
        let lessonIDsInGroup = Set(lessonsInGroup.compactMap { $0.id?.uuidString })
        var presentedLessonIDs = Set<String>()
        for assignment in presentedAssignments {
            guard lessonIDsInGroup.contains(assignment.lessonID) else { continue }
            if assignment.studentUUIDs.contains(studentID) {
                presentedLessonIDs.insert(assignment.lessonID)
            }
        }

        // Find first unpresented lesson
        if let firstUnpresented = lessonsInGroup.first(where: {
            guard let id = $0.id?.uuidString else { return false }
            return !presentedLessonIDs.contains(id)
        }) {
            allLessonsPresentedInGroup = false
            selectedLesson = firstUnpresented
        } else {
            // All presented — default to first lesson for re-scheduling
            allLessonsPresentedInGroup = true
            selectedLesson = lessonsInGroup.first
        }
    }

    func computePreview(context: NSManagedObjectContext) async {
        guard let lesson = selectedLesson,
              lesson.id != nil else {
            previewItems = []
            showsOverflowWarning = false
            overflowCount = 0
            return
        }

        // Fetch all lessons in the same subject + group
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(
            format: "subject ==[c] %@ AND group ==[c] %@",
            lesson.subject, lesson.group
        )
        req.sortDescriptors = [NSSortDescriptor(key: "orderInGroup", ascending: true)]
        let allInGroup = context.safeFetch(req)

        // Filter to lessons at or after the selected lesson's orderInGroup
        let sequence = allInGroup.filter { $0.orderInGroup >= lesson.orderInGroup }
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

            items.append(PreviewItem(
                id: lessonInSequence.id ?? UUID(),
                lesson: lessonInSequence,
                lessonName: lessonInSequence.name,
                subject: lessonInSequence.subject,
                date: currentDate,
                alreadyExists: false,
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

        let sequenceGroupKey = "\(lesson.subject)::\(lesson.group)"

        for item in previewItems {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = studentID.uuidString
            entry.lessonID = item.id.uuidString
            entry.plannedDate = item.date
            entry.spacingSchoolDays = Int64(spacingDays)
            entry.sequenceGroupKey = sequenceGroupKey
            entry.orderInSequence = Int64(item.orderInSequence)
            entry.status = .planned
        }

        context.safeSave()
    }
}
