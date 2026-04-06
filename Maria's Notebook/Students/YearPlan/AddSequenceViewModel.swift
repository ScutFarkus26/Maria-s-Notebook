import Foundation
import CoreData

@Observable
@MainActor
final class AddSequenceViewModel {
    var selectedLesson: CDLesson?
    var startDate: Date = Date()
    var spacingDays: Int = 3

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
