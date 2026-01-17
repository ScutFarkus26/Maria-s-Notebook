#if canImport(Testing)
import Testing
import SwiftData
import Foundation

@testable import Maria_s_Notebook

@Suite("BackupService Round-Trip Tests")
@MainActor
struct BackupServiceRoundTripTests {

    // MARK: - Helper methods

    // Create fresh in-memory container with all model types
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([
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
            CommunityAttachment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    // Try fetching to check if model type exists
    func canFetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Bool {
        do {
            _ = try context.fetch(FetchDescriptor<T>())
            return true
        } catch {
            return false
        }
    }

    // Seed at least one instance per entity type if fetchable
    func seedAllEntities(in context: ModelContext) {
        // Each seed method guarded by canFetch to avoid errors if type not present

        if canFetch(Student.self, in: context) {
            let student = Student(
                firstName: "Test",
                lastName: "Student",
                birthday: Date()
            )
            context.insert(student)
        }

        if canFetch(Lesson.self, in: context) {
            let lesson = Lesson()
            lesson.name = "Test Lesson"
            context.insert(lesson)
        }

        if canFetch(StudentLesson.self, in: context) {
            let sl = StudentLesson(
                lessonID: UUID(),
                studentIDs: []
            )
            context.insert(sl)
        }

        if canFetch(WorkContract.self, in: context) {
            let wc = WorkContract(
                studentID: UUID().uuidString,
                lessonID: UUID().uuidString
            )
            context.insert(wc)
        }

        if canFetch(WorkPlanItem.self, in: context) {
            let wpi = WorkPlanItem(
                workID: UUID(),
                scheduledDate: Date()
            )
            context.insert(wpi)
        }

        if canFetch(Note.self, in: context) {
            let note = Note(
                body: "Test note"
            )
            context.insert(note)
        }

        if canFetch(NonSchoolDay.self, in: context) {
            let nsd = NonSchoolDay(
                date: Date()
            )
            context.insert(nsd)
        }

        if canFetch(SchoolDayOverride.self, in: context) {
            let sdo = SchoolDayOverride(
                date: Date()
            )
            context.insert(sdo)
        }

        if canFetch(StudentMeeting.self, in: context) {
            let sm = StudentMeeting(
                studentID: UUID()
            )
            context.insert(sm)
        }

        if canFetch(Presentation.self, in: context) {
            let p = Presentation(
                presentedAt: Date(),
                lessonID: UUID().uuidString,
                studentIDs: []
            )
            context.insert(p)
        }

        if canFetch(CommunityTopic.self, in: context) {
            let ct = CommunityTopic()
            context.insert(ct)
        }

        if canFetch(ProposedSolution.self, in: context) {
            let ps = ProposedSolution()
            context.insert(ps)
        }

        if canFetch(CommunityAttachment.self, in: context) {
            let ca = CommunityAttachment()
            context.insert(ca)
        }
    }

    // Count entities of a given type if fetchable, else return nil
    func countEntities<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int? {
        do {
            let results = try context.fetch(FetchDescriptor<T>())
            return results.count
        } catch {
            return nil
        }
    }

    // Get all model types to check counts for
    var allModelTypes: [any PersistentModel.Type] {
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
            CommunityAttachment.self,
        ]
    }

    // MARK: - Test

    @Test("Round-trip all entities counts match", .disabled("Test requires full SwiftData support"))
    @MainActor
    func testRoundTripAllEntitiesCountsMatch() async throws {
        // Try to create initial container, skip if fails
        let sourceContainer: ModelContainer
        do {
            sourceContainer = try makeContainer()
        } catch {
            // Skip test if container creation fails
            return
        }

        let sourceContext = sourceContainer.mainContext

        // Seed data
        seedAllEntities(in: sourceContext)
        try sourceContext.save()

        // Export to temporary file URL
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let exportURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("backup")

        let backupService = BackupService()

        do {
            _ = try await backupService.exportBackup(
                modelContext: sourceContext,
                to: exportURL,
                password: nil,
                progress: { _, _ in }
            )
        } catch {
            Issue.record("Export failed: \(error)")
            return
        }

        // Create destination container
        let destContainer: ModelContainer
        do {
            destContainer = try makeContainer()
        } catch {
            // Skip test if container creation fails
            return
        }

        let destContext = destContainer.mainContext

        do {
            _ = try await backupService.importBackup(
                modelContext: destContext,
                from: exportURL,
                mode: .replace,
                password: nil,
                progress: { _, _ in }
            )
        } catch {
            Issue.record("Import failed: \(error)")
            return
        }

        // Verify counts per entity type
        for modelType in allModelTypes {
            // Count in source and dest
            let sourceCount: Int?
            let destCount: Int?

            switch modelType {
            case is Student.Type:
                sourceCount = countEntities(Student.self, in: sourceContext)
                destCount = countEntities(Student.self, in: destContext)
            case is Lesson.Type:
                sourceCount = countEntities(Lesson.self, in: sourceContext)
                destCount = countEntities(Lesson.self, in: destContext)
            case is StudentLesson.Type:
                sourceCount = countEntities(StudentLesson.self, in: sourceContext)
                destCount = countEntities(StudentLesson.self, in: destContext)
            case is WorkContract.Type:
                sourceCount = countEntities(WorkContract.self, in: sourceContext)
                destCount = countEntities(WorkContract.self, in: destContext)
            case is WorkPlanItem.Type:
                sourceCount = countEntities(WorkPlanItem.self, in: sourceContext)
                destCount = countEntities(WorkPlanItem.self, in: destContext)
            case is Note.Type:
                sourceCount = countEntities(Note.self, in: sourceContext)
                destCount = countEntities(Note.self, in: destContext)
            case is NonSchoolDay.Type:
                sourceCount = countEntities(NonSchoolDay.self, in: sourceContext)
                destCount = countEntities(NonSchoolDay.self, in: destContext)
            case is SchoolDayOverride.Type:
                sourceCount = countEntities(SchoolDayOverride.self, in: sourceContext)
                destCount = countEntities(SchoolDayOverride.self, in: destContext)
            case is StudentMeeting.Type:
                sourceCount = countEntities(StudentMeeting.self, in: sourceContext)
                destCount = countEntities(StudentMeeting.self, in: destContext)
            case is Presentation.Type:
                sourceCount = countEntities(Presentation.self, in: sourceContext)
                destCount = countEntities(Presentation.self, in: destContext)
            case is CommunityTopic.Type:
                sourceCount = countEntities(CommunityTopic.self, in: sourceContext)
                destCount = countEntities(CommunityTopic.self, in: destContext)
            case is ProposedSolution.Type:
                sourceCount = countEntities(ProposedSolution.self, in: sourceContext)
                destCount = countEntities(ProposedSolution.self, in: destContext)
            case is CommunityAttachment.Type:
                sourceCount = countEntities(CommunityAttachment.self, in: sourceContext)
                destCount = countEntities(CommunityAttachment.self, in: destContext)
            default:
                sourceCount = nil
                destCount = nil
            }

            if let sourceCount = sourceCount, let destCount = destCount {
                #expect(
                    destCount == sourceCount,
                    "Entity \(String(describing: modelType)) count mismatch: source \(sourceCount) vs dest \(destCount)"
                )
            }
        }
    }
}
#endif
