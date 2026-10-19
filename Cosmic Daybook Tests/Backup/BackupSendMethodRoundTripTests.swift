import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Backup v40 carries schema 18's four fields: how attendance goes to the
/// school (`sendMethodRaw`, `parentLockerSite`), which way each send went
/// (`channelRaw`), and a child's ParentLocker match (`parentLockerID`). A v39
/// backup restores as email and leaves a record's own values.
@Suite("Backup: attendance send method (v40)", .serialized)
@MainActor
struct BackupSendMethodRoundTripTests {

    private static let settingsID = UUID()
    private static let sendID = UUID()
    private static let studentID = UUID()

    private func student(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDStudent? {
        try BackupTestUtil.fetchByID(CDStudent.self, id, entityName: "Student", in: context)
    }

    private func send(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDAttendanceEmailSend? {
        try BackupTestUtil.fetchByID(CDAttendanceEmailSend.self, id, entityName: "AttendanceEmailSend", in: context)
    }

    private func seedParentLocker(in context: NSManagedObjectContext) throws -> (CDStudent, CDAttendanceEmailSend) {
        let maya = CDStudent(context: context)
        maya.firstName = "Maya"
        maya.lastName = "Stone"
        maya.parentLockerID = "48213"
        var settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        settings.sendMethod = .parentLocker
        settings.parentLockerSite = "other.parentlocker.com"
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context))
        let send = AttendanceEmailLog.recordSend(
            on: try CoreDataTestHelpers.day("2026-10-12"), role: .assistant, channel: .parentLocker, in: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return (maya, send)
    }

    @Test("v40: the method, site, channel and a child's match survive a Replace restore")
    func allFourFieldsRoundTrip() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let (maya, send) = try seedParentLocker(in: source)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        #expect(try student(maya.id, in: restored)?.parentLockerID == "48213")
        #expect(try self.send(send.id, in: restored)?.channelRaw == "parentLocker")
        let row = try #require(restored.safeFetchFirst(CDFetchRequest(CDAttendanceEmailSettings.self)))
        #expect(row.sendMethodRaw == "parentLocker")
        #expect(row.parentLockerSite == "other.parentlocker.com")
        #expect(!row.isEnabled)
        // v40 brought these fields; later formats still carry them.
        #expect(BackupWriter.formatVersion >= 40)
        #expect(BackupReader.supportedFormatVersions.contains(39))
    }

    @Test("A v39 backup restores as email into a fresh store")
    func v39RestoresAsEmail() async throws {
        let fresh = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await restoreV39(try v39Payload(), into: fresh)

        let settings = try #require(AttendanceEmailLog.settings(in: fresh))
        #expect(settings.sendMethod == .email)
        #expect(settings.parentLockerSite == "yyli.parentlocker.com")
        #expect(settings.canSend)
        #expect(try send(Self.sendID, in: fresh)?.channelRaw == "email")
        let maya = try #require(try student(Self.studentID, in: fresh))
        #expect(maya.firstName == "Maya")
        #expect(maya.parentLockerID == nil)
    }

    @Test("A v39 backup merged over schema 18 records leaves their method, site, channel and match")
    func v39MergeKeepsOwnValues() async throws {
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let row = CDAttendanceEmailSettings(context: target)
        row.id = Self.settingsID
        row.sendMethodRaw = "parentLocker"
        row.parentLockerSite = "other.parentlocker.com"
        let send = CDAttendanceEmailSend(context: target)
        send.id = Self.sendID
        send.channelRaw = "parentLocker"
        let maya = CDStudent(context: target)
        maya.id = Self.studentID
        maya.firstName = "Maya"
        maya.lastName = "Stone"
        maya.parentLockerID = "48213"
        #expect(CoreDataTestHelpers.save(target))

        try await restoreV39(try v39Payload(), into: target)

        #expect(row.sendMethodRaw == "parentLocker", "a v39 row has no method to put over it")
        #expect(row.parentLockerSite == "other.parentlocker.com")
        #expect(row.toAddresses == "office@school.org", "the rest of the row restores")
        #expect(send.channelRaw == "parentLocker")
        #expect(send.sentBy == "assistant")
        #expect(maya.parentLockerID == "48213", "a v39 student has no match to put over it")
    }

    // MARK: - A v39 backup

    /// One settings row, one send and one student, as a v39 backup wrote them.
    private func v39Payload() throws -> BackupPayload {
        let settingsRow = #"{"deadlineMinutes":540,"groupByLevel":false,"id":"\#(Self.settingsID.uuidString)","#
            + #""isEnabled":true,"modifiedAt":"2026-10-01T12:00:00Z","nameOrderRaw":"firstLast","#
            + #""toAddresses":"office@school.org"}"#
        let sendRow = #"{"date":"2026-10-12T04:00:00Z","id":"\#(Self.sendID.uuidString)","#
            + #""sentAt":"2026-10-12T12:42:00Z","sentBy":"assistant","wasConfirmedByHand":false}"#
        let studentRow = #"{"firstName":"Maya","id":"\#(Self.studentID.uuidString)","lastName":"Stone","#
            + #""level":"upper","manualOrder":0,"nextLessons":[]}"#
        let rows = [("AttendanceEmailSettings", settingsRow), ("AttendanceEmailSend", sendRow), ("Student", studentRow)]
        let decoded = BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: 39, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: rows.map { name, row in
                BackupEntityEntry(entityName: name, storeName: "shared", count: 1, ndjson: Data((row + "\n").utf8))
            },
            preferences: nil
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        #expect(payload.attendanceEmailSettings?.count == 1, "a v39 row decodes without the v40 keys")
        #expect(payload.attendanceEmailSends?.count == 1)
        #expect(payload.students.count == 1)
        return payload
    }

    private func restoreV39(_ payload: BackupPayload, into context: NSManagedObjectContext) async throws {
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: 39, encrypted: false, createdAt: Date(), fileName: "v39", entityCounts: [:]
            ),
            viewContext: context,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
    }
}
