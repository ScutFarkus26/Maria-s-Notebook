import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Sample Classroom", .serialized)
@MainActor
final class SampleClassroomTests {
    @Test("Sample records live in a different store while lessons are mirrored")
    func isolatedStoreAndSharedLessonCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let primaryURL = directory.appendingPathComponent("primary.sqlite")
        let sampleURL = directory.appendingPathComponent("sample.sqlite")
        let primaryStack = try CoreDataStack(enableCloudKit: false, localStoreURL: primaryURL)
        let sampleStack = try CoreDataStack(enableCloudKit: false, localStoreURL: sampleURL)

        let primaryContext = primaryStack.viewContext
        let lesson = CoreDataTestHelpers.seedLesson(
            in: primaryContext,
            name: "The Decimal System",
            area: "Mathematics",
            sequence: "Numeration"
        )
        let lessonID = try #require(lesson.id)
        lesson.writeUp = "Primary classroom lesson write-up"
        try primaryContext.save()

        try SampleClassroomSeeder.prepare(
            lessonsFrom: primaryContext,
            sampleContext: sampleStack.viewContext
        )

        #expect(primaryURL != sampleURL)
        #expect(primaryStack.container.persistentStoreCoordinator.persistentStores.first?.url == primaryURL)
        #expect(sampleStack.container.persistentStoreCoordinator.persistentStores.first?.url == sampleURL)

        let sampleStudents = try sampleStack.viewContext.fetch(CDFetchRequest(CDStudent.self))
        #expect(sampleStudents.count == 8)
        #expect(try primaryContext.count(for: CDFetchRequest(CDStudent.self)) == 0)

        let sampleLessonRequest = CDFetchRequest(CDLesson.self)
        sampleLessonRequest.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        let sampleLesson = try #require(sampleStack.viewContext.fetch(sampleLessonRequest).first)
        #expect(sampleLesson.name == "The Decimal System")
        #expect(sampleLesson.writeUp == lesson.writeUp)
        #expect(sampleLesson.objectID.persistentStore == sampleStack.container.persistentStoreCoordinator.persistentStores.first)

        let extraSampleStudent = CDStudent(context: sampleStack.viewContext)
        extraSampleStudent.firstName = "Only"
        extraSampleStudent.lastName = "In Sample"
        sampleLesson.name = "Changed only in Sample Class"
        try sampleStack.viewContext.save()

        #expect(lesson.name == "The Decimal System")
        #expect(try primaryContext.count(for: CDFetchRequest(CDStudent.self)) == 0)
    }

    @Test("Reopening Sample Class refreshes its mirrored lesson values")
    func lessonRefresh() throws {
        let primaryStack = try CoreDataTestHelpers.makeInMemoryStack()
        let sampleStack = try CoreDataTestHelpers.makeInMemoryStack()
        let primaryLesson = CoreDataTestHelpers.seedLesson(in: primaryStack.viewContext, name: "Initial Name")
        let lessonID = try #require(primaryLesson.id)
        try primaryStack.viewContext.save()

        try SampleClassroomSeeder.prepare(
            lessonsFrom: primaryStack.viewContext,
            sampleContext: sampleStack.viewContext
        )

        primaryLesson.name = "Updated Name"
        try primaryStack.viewContext.save()
        try SampleClassroomSeeder.prepare(
            lessonsFrom: primaryStack.viewContext,
            sampleContext: sampleStack.viewContext
        )

        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        let mirroredLesson = try #require(sampleStack.viewContext.fetch(request).first)
        #expect(mirroredLesson.name == "Updated Name")
    }

    @Test("Opening Sample Class does not wake the real classroom's CloudKit monitor")
    func sampleStoreNotificationsStayIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let primaryStack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("primary.sqlite")
        )
        let syncMonitor = CloudKitSyncStatusService(coreDataStack: primaryStack)
        syncMonitor.startObserving()
        defer { syncMonitor.removeAllObservers() }

        let sampleStack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("sample.sqlite"),
            managedObjectModel: primaryStack.container.managedObjectModel
        )
        #expect(sampleStack.container.managedObjectModel === primaryStack.container.managedObjectModel)
        let sampleStudent = CDStudent(context: sampleStack.viewContext)
        sampleStudent.firstName = "Sample"
        sampleStudent.lastName = "Only"
        try sampleStack.viewContext.save()
        await Task.yield()

        #expect(syncMonitor.pendingStoreChangeTask == nil)
        #expect(syncMonitor.pendingSaveTask == nil)
    }
}
