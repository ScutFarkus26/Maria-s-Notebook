import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #44: deleting a project left its old template-week,
/// role-assignment and assignment-template rows behind, and backups carried
/// them. They are the project's alone, so they go with it; another
/// project's stay.
@Suite("Project deletion leftovers (fix 10-17 St)")
@MainActor
struct ProjectDeletionFix1017StTests {

    private struct Rows {
        let week: NSManagedObject
        let roleAssignment: NSManagedObject
        let assignmentTemplate: NSManagedObject
    }

    private func insert(_ entity: String, in context: NSManagedObjectContext) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        row.setValue(UUID(), forKey: "id")
        return row
    }

    /// One template week with a role assignment on it, and one assignment
    /// template, all for `project`.
    private func seedRows(for project: CDProject, in context: NSManagedObjectContext) throws -> Rows {
        let projectID = try #require(project.id).uuidString
        let week = insert("ProjectTemplateWeek", in: context)
        week.setValue(projectID, forKey: "projectID")
        let roleAssignment = insert("ProjectWeekRoleAssignment", in: context)
        roleAssignment.setValue((week.value(forKey: "id") as? UUID)?.uuidString ?? "", forKey: "weekID")
        roleAssignment.setValue(week, forKey: "week")
        let template = insert("ProjectAssignmentTemplate", in: context)
        template.setValue(projectID, forKey: "projectID")
        template.setValue(project, forKey: "project")
        return Rows(week: week, roleAssignment: roleAssignment, assignmentTemplate: template)
    }

    private func isGone(_ object: NSManagedObject) -> Bool {
        object.isDeleted || object.managedObjectContext == nil
    }

    @Test("A deleted project takes its template weeks, their role assignments and its assignment templates")
    func projectRowsGoWithIt() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let doomed = CDProject(context: context)
        let kept = CDProject(context: context)
        let doomedRows = try seedRows(for: doomed, in: context)
        let keptRows = try seedRows(for: kept, in: context)
        #expect(CoreDataTestHelpers.save(context))

        ProjectDeletion.delete(doomed, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(isGone(doomed))
        #expect(isGone(doomedRows.week))
        #expect(isGone(doomedRows.roleAssignment))
        #expect(isGone(doomedRows.assignmentTemplate))
        #expect(!isGone(kept))
        #expect(!isGone(keptRows.week))
        #expect(!isGone(keptRows.roleAssignment))
        #expect(!isGone(keptRows.assignmentTemplate))
    }
}
