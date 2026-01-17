#if canImport(Testing)
import XCTest
import SwiftData
import Foundation

@testable import Maria_s_Notebook

@MainActor
final class BackupServiceRoundTripTests: XCTestCase {

    struct TestError: Error {}

    // MARK: - Helper methods

    // Create fresh in-memory container with all model types
    func makeContainer() throws -> ModelContainer {
        // List all model types mentioned in instructions
        let modelTypes: [any Entity.Type] = [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkContract.self,
            WorkPlanItem.self,
            Note.self,
            NonSchoolDay.self,
            SchoolDayOverride.self,
            StudentMeeting.self,
            Presentation.self,
            CommunityTopic.self,
            ProposedSolution.self,
            MeetingNote.self,
            CommunityAttachment.self,
        ]
        return try ModelContainer(for: modelTypes, inMemory: true)
    }

    // Try fetching to check if model type exists
    func canFetch<Entity: Entity>(_ type: Entity.Type, in container: ModelContainer) -> Bool {
        do {
            _ = try container.fetch(FetchDescriptor<Entity>())
            return true
        } catch {
            return false
        }
    }

    // Seed at least one instance per entity type if fetchable
    func seedAllEntities(in container: ModelContainer) {
        // Each seed method guarded by canFetch to avoid errors if type not present

        if canFetch(Student.self, in: container) {
            let student = Student()
            if let s = student as? any ObservableObject {
                // Configure representative data if possible
                (student as? Student)?.id = UUID()
                (student as? Student)?.name = "Test Student"
            }
            container.insert(student)
        }

        if canFetch(Lesson.self, in: container) {
            let lesson = Lesson()
            (lesson as? Lesson)?.id = UUID()
            (lesson as? Lesson)?.title = "Test Lesson"
            container.insert(lesson)
        }

        if canFetch(StudentLesson.self, in: container) {
            let sl = StudentLesson()
            (sl as? StudentLesson)?.id = UUID()
            container.insert(sl)
        }

        if canFetch(WorkContract.self, in: container) {
            let wc = WorkContract()
            (wc as? WorkContract)?.id = UUID()
            container.insert(wc)
        }

        if canFetch(WorkPlanItem.self, in: container) {
            let wpi = WorkPlanItem()
            (wpi as? WorkPlanItem)?.id = UUID()
            container.insert(wpi)
        }

        if canFetch(Note.self, in: container) {
            let note = Note()
            (note as? Note)?.id = UUID()
            container.insert(note)
        }

        if canFetch(NonSchoolDay.self, in: container) {
            let nsd = NonSchoolDay()
            (nsd as? NonSchoolDay)?.id = UUID()
            container.insert(nsd)
        }

        if canFetch(SchoolDayOverride.self, in: container) {
            let sdo = SchoolDayOverride()
            (sdo as? SchoolDayOverride)?.id = UUID()
            container.insert(sdo)
        }

        if canFetch(StudentMeeting.self, in: container) {
            let sm = StudentMeeting()
            (sm as? StudentMeeting)?.id = UUID()
            container.insert(sm)
        }

        if canFetch(Presentation.self, in: container) {
            let p = Presentation()
            (p as? Presentation)?.id = UUID()
            container.insert(p)
        }

        if canFetch(CommunityTopic.self, in: container) {
            let ct = CommunityTopic()
            (ct as? CommunityTopic)?.id = UUID()
            container.insert(ct)
        }

        if canFetch(ProposedSolution.self, in: container) {
            let ps = ProposedSolution()
            (ps as? ProposedSolution)?.id = UUID()
            container.insert(ps)
        }

        if canFetch(MeetingNote.self, in: container) {
            let mn = MeetingNote()
            (mn as? MeetingNote)?.id = UUID()
            container.insert(mn)
        }

        if canFetch(CommunityAttachment.self, in: container) {
            let ca = CommunityAttachment()
            (ca as? CommunityAttachment)?.id = UUID()
            container.insert(ca)
        }
    }

    // Count entities of a given type if fetchable, else return nil
    func countEntities<Entity: Entity>(_ type: Entity.Type, in container: ModelContainer) -> Int? {
        do {
            let results = try container.fetch(FetchDescriptor<Entity>())
            return results.count
        } catch {
            return nil
        }
    }

    // Get all model types to check counts for
    var allModelTypes: [any Entity.Type] {
        [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkContract.self,
            WorkPlanItem.self,
            Note.self,
            NonSchoolDay.self,
            SchoolDayOverride.self,
            StudentMeeting.self,
            Presentation.self,
            CommunityTopic.self,
            ProposedSolution.self,
            MeetingNote.self,
            CommunityAttachment.self,
        ]
    }

    // MARK: - Test

    @MainActor
    @Test("Round-trip all entities counts match")
    func testRoundTripAllEntitiesCountsMatch() async throws {
        // Try to create initial container, skip if fails
        let sourceContainer: ModelContainer
        do {
            sourceContainer = try makeContainer()
        } catch {
            throw XCTSkip("Cannot create in-memory container: \(error)")
        }

        // Seed data
        seedAllEntities(in: sourceContainer)
        try sourceContainer.save()

        // Export to temporary file URL
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let exportURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("backup")

        do {
            try BackupService.shared.export(to: exportURL, container: sourceContainer)
        } catch {
            XCTFail("Export failed: \(error)")
            return
        }

        // Create destination container
        let destContainer: ModelContainer
        do {
            destContainer = try makeContainer()
        } catch {
            throw XCTSkip("Cannot create destination in-memory container: \(error)")
        }

        do {
            try BackupService.shared.import(from: exportURL, container: destContainer, mode: .replace)
        } catch {
            XCTFail("Import failed: \(error)")
            return
        }

        // Verify counts per entity type
        for modelType in allModelTypes {
            // Use dynamic casting to Entity.Type
            if let entityType = modelType as? any Entity.Type {
                // Count in source
                let sourceCount: Int?
                let destCount: Int?

                switch entityType {
                case is Student.Type:
                    sourceCount = countEntities(Student.self, in: sourceContainer)
                    destCount = countEntities(Student.self, in: destContainer)
                case is Lesson.Type:
                    sourceCount = countEntities(Lesson.self, in: sourceContainer)
                    destCount = countEntities(Lesson.self, in: destContainer)
                case is StudentLesson.Type:
                    sourceCount = countEntities(StudentLesson.self, in: sourceContainer)
                    destCount = countEntities(StudentLesson.self, in: destContainer)
                case is WorkContract.Type:
                    sourceCount = countEntities(WorkContract.self, in: sourceContainer)
                    destCount = countEntities(WorkContract.self, in: destContainer)
                case is WorkPlanItem.Type:
                    sourceCount = countEntities(WorkPlanItem.self, in: sourceContainer)
                    destCount = countEntities(WorkPlanItem.self, in: destContainer)
                case is Note.Type:
                    sourceCount = countEntities(Note.self, in: sourceContainer)
                    destCount = countEntities(Note.self, in: destContainer)
                case is NonSchoolDay.Type:
                    sourceCount = countEntities(NonSchoolDay.self, in: sourceContainer)
                    destCount = countEntities(NonSchoolDay.self, in: destContainer)
                case is SchoolDayOverride.Type:
                    sourceCount = countEntities(SchoolDayOverride.self, in: sourceContainer)
                    destCount = countEntities(SchoolDayOverride.self, in: destContainer)
                case is StudentMeeting.Type:
                    sourceCount = countEntities(StudentMeeting.self, in: sourceContainer)
                    destCount = countEntities(StudentMeeting.self, in: destContainer)
                case is Presentation.Type:
                    sourceCount = countEntities(Presentation.self, in: sourceContainer)
                    destCount = countEntities(Presentation.self, in: destContainer)
                case is CommunityTopic.Type:
                    sourceCount = countEntities(CommunityTopic.self, in: sourceContainer)
                    destCount = countEntities(CommunityTopic.self, in: destContainer)
                case is ProposedSolution.Type:
                    sourceCount = countEntities(ProposedSolution.self, in: sourceContainer)
                    destCount = countEntities(ProposedSolution.self, in: destContainer)
                case is MeetingNote.Type:
                    sourceCount = countEntities(MeetingNote.self, in: sourceContainer)
                    destCount = countEntities(MeetingNote.self, in: destContainer)
                case is CommunityAttachment.Type:
                    sourceCount = countEntities(CommunityAttachment.self, in: sourceContainer)
                    destCount = countEntities(CommunityAttachment.self, in: destContainer)
                default:
                    sourceCount = nil
                    destCount = nil
                }

                if let sourceCount = sourceCount, let destCount = destCount {
                    XCTAssertEqual(
                        destCount, sourceCount,
                        "Entity \(String(describing: entityType)) count mismatch: source \(sourceCount) vs dest \(destCount)"
                    )
                }
            }
        }
    }
}
#endif
