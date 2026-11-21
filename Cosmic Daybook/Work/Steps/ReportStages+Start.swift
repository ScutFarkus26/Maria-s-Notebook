// ReportStages+Start.swift
// Starting a report from a meeting: one copy for each child writing it,
// linked to each other the way Quick New Work links them, at Topic.

import CoreData
import Foundation

extension ReportStages {

    /// The lessons a report can come from: those whose work is a report by
    /// default, and those named as reports ("Research Report", "Book
    /// Report: New"), by name.
    static func reportLessons(in context: NSManagedObjectContext) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(
            format: "defaultWorkKindRaw == %@ OR name CONTAINS[cd] %@", WorkKind.report.rawValue, "report"
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        return context.safeFetch(request).filter { !$0.name.trimmed().isEmpty }
    }

    /// Makes the report for each child, the first one owning the first copy,
    /// with the five stages and linked to each other. Doesn't save; throws
    /// when a child has left the class.
    @discardableResult
    static func startReport(
        title: String, studentIDs: [UUID], lessonID: UUID, context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: context)
        var created: [CDWorkModel] = []
        for studentID in studentIDs {
            let work = try repository.createWork(
                studentID: studentID, lessonID: lessonID, title: title.trimmed(), kind: .report,
                saveImmediately: false
            )
            addStandardSteps(to: work, context: context)
            created.append(work)
        }
        // One assignment given to a group: the copies name each other and
        // share an assignment id, as work from New Work does.
        WorkAssignmentService.link(created, in: context)
        return created
    }
}
