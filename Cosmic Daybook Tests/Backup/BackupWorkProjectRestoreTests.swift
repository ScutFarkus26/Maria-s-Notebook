import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The links a restore re-makes for work and projects, since "Simplify round
/// two", Phase 7 moved their rows onto row specs: a check-in and a child on a
/// piece of work are filed under the work, a project session under its
/// project, each restored before them. The spec oracle's golden child names
/// no work, and its check-in and session only ever name a parent that is
/// there, so these are checked here:
///
/// - To the parent the row names when it is here; a row naming one that
///   isn't, or (a child) none, leaves the link as it is, as the hand-written
///   importers did.
/// - A check-in whose `workID` isn't an id is passed over: the record keeps
///   its own.
@Suite("Backup: work's check-ins and children, and project sessions, under their parents", .serialized)
@MainActor
struct BackupWorkProjectRestoreTests {

    /// A record of `type` from the fixture.
    private static func any<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> T {
        try #require(context.safeFetch(CDFetchRequest(type)).first, "the fixture holds a \(type)")
    }

    /// The fixture's check-in, child and session, each under its parent.
    private struct Linked {
        let checkIn: CDWorkCheckIn
        let participant: CDWorkParticipantEntity
        let session: CDProjectSession
    }

    /// A store holding the field-coverage fixture, its check-in and child
    /// filed under its work and its session under its project.
    private static func linkedFixture() throws -> (CoreDataStack, Linked) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        let work = try any(CDWorkModel.self, in: context)
        let project = try any(CDProject.self, in: context)
        let linked = Linked(
            checkIn: try any(CDWorkCheckIn.self, in: context),
            participant: try any(CDWorkParticipantEntity.self, in: context),
            session: try any(CDProjectSession.self, in: context)
        )
        linked.checkIn.work = work
        linked.checkIn.workID = work.id?.uuidString ?? ""
        linked.participant.work = work
        linked.session.project = project
        linked.session.projectID = project.id?.uuidString ?? ""
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return (stack, linked)
    }

    @Test("Through an archive into an empty notebook, each comes back under its parent")
    func linksComeBack() async throws {
        let (source, linked) = try Self.linkedFixture()
        let checkInID = try #require(linked.checkIn.id)
        let participantID = try #require(linked.participant.id)
        let sessionID = try #require(linked.session.id)
        let workID = try #require(linked.participant.work?.id)
        let projectID = try #require(linked.session.project?.id)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source.viewContext, to: url)
        // Merge into an empty notebook does what Replace would (BackupRoundTripTests).
        let restoredStack = try CoreDataTestHelpers.makeInMemoryStack()
        let restored = restoredStack.viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .merge)

        let checkIn = try BackupTestUtil.fetchByID(
            CDWorkCheckIn.self, checkInID, entityName: "WorkCheckIn", in: restored
        )
        let participant = try BackupTestUtil.fetchByID(
            CDWorkParticipantEntity.self, participantID, entityName: "WorkParticipantEntity", in: restored
        )
        let session = try BackupTestUtil.fetchByID(
            CDProjectSession.self, sessionID, entityName: "ProjectSession", in: restored
        )
        #expect(checkIn?.work?.id == workID)
        #expect(participant?.work?.id == workID)
        #expect(session?.project?.id == projectID)
    }

    @Test("A Merge files a child under the work its row names, and leaves it when that isn't here")
    func mergeRelinksTheChildsWork() async throws {
        let (stack, linked) = try Self.linkedFixture()
        let context = stack.viewContext
        let participantID = try #require(linked.participant.id)
        let otherID = try Self.otherWork(in: context)

        /// A Merge of this notebook's backup with the child's `workID` set to `workID`.
        func restore(workID: UUID?) async throws -> UUID? {
            var backup = Fix1102.payload(of: context)
            let rows = try #require(backup.workParticipants)
            let row = try #require(rows.firstIndex { $0.id == participantID })
            backup.workParticipants?[row].values["workID"] = workID.map(ModelValue.uuid)
            try await Fix1102.restore(backup, into: context, mode: .merge)
            let restored = try BackupTestUtil.fetchByID(
                CDWorkParticipantEntity.self, participantID, entityName: "WorkParticipantEntity", in: context
            )
            return restored?.work?.id
        }

        #expect(try await restore(workID: otherID) == otherID, "filed under the work the row names")
        #expect(try await restore(workID: UUID()) == otherID, "left as it is: the row's work isn't here")
        #expect(try await restore(workID: nil) == otherID, "left as it is: the row names no work")
    }

    @Test("A Merge files a check-in under the work its row names, and passes over one that names no id")
    func mergeRelinksTheCheckInsWork() async throws {
        let (stack, linked) = try Self.linkedFixture()
        let context = stack.viewContext
        let checkInID = try #require(linked.checkIn.id)
        let otherID = try Self.otherWork(in: context)

        /// A Merge of this notebook's backup with the check-in's `workID` set
        /// to `workID`: the check-in's work and `workID` after it.
        func restore(workID: String) async throws -> (work: UUID?, workID: String?) {
            var backup = Fix1102.payload(of: context)
            let rows = try #require(backup.workCheckIns)
            let row = try #require(rows.firstIndex { $0.id == checkInID })
            backup.workCheckIns?[row].values["workID"] = .string(workID)
            try await Fix1102.restore(backup, into: context, mode: .merge)
            let restored = try BackupTestUtil.fetchByID(
                CDWorkCheckIn.self, checkInID, entityName: "WorkCheckIn", in: context
            )
            return (restored?.work?.id, restored?.workID)
        }

        let named = try await restore(workID: otherID.uuidString)
        #expect(named.work == otherID && named.workID == otherID.uuidString, "filed under the work the row names")
        let missing = UUID().uuidString
        let notHere = try await restore(workID: missing)
        #expect(notHere.work == otherID, "left as it is: the row's work isn't here")
        #expect(notHere.workID == missing, "the row's id restores as it is")
        let notAnID = try await restore(workID: "not an id")
        #expect(notAnID.work == otherID && notAnID.workID == missing, "passed over: the record keeps its own")
    }

    @Test("A Merge files a session under the project its row names, and leaves it when that isn't here")
    func mergeRelinksTheSessionsProject() async throws {
        let (stack, linked) = try Self.linkedFixture()
        let context = stack.viewContext
        let sessionID = try #require(linked.session.id)
        let other = CDProject(context: context)
        other.title = "Other project"
        let otherID = try #require(other.id)
        #expect(CoreDataTestHelpers.save(context))
        #expect(linked.session.project?.id != otherID, "the fixture files it under another project")

        /// A Merge of this notebook's backup with the session's `projectID` set to `projectID`.
        func restore(projectID: UUID) async throws -> UUID? {
            var backup = Fix1102.payload(of: context)
            let row = try #require(backup.projectSessions.firstIndex { $0.id == sessionID })
            backup.projectSessions[row].values["projectID"] = .uuid(projectID)
            try await Fix1102.restore(backup, into: context, mode: .merge)
            let restored = try BackupTestUtil.fetchByID(
                CDProjectSession.self, sessionID, entityName: "ProjectSession", in: context
            )
            return restored?.project?.id
        }

        #expect(try await restore(projectID: otherID) == otherID, "filed under the project the row names")
        #expect(try await restore(projectID: UUID()) == otherID, "left as it is: the row's project isn't here")
    }

    /// A second piece of work in `context`, saved, by id.
    private static func otherWork(in context: NSManagedObjectContext) throws -> UUID {
        let other = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Other work", studentID: UUID(), lessonID: UUID()
        )
        let otherID = try #require(other.id)
        #expect(CoreDataTestHelpers.save(context))
        return otherID
    }
}
