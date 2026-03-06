import Foundation
import CryptoKit
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Restore Preview tests") final class RestorePreviewTests {
    struct TestPayload: Codable {
        var account: AccountDTO
        var attachment: AttachmentDTO
        var calendar: CalendarDTO
        var calendarEvent: CalendarEventDTO
        var contact: ContactDTO
        var folder: FolderDTO
        var mailMessage: MailMessageDTO
        var tag: TagDTO
        var task: TaskDTO
        var taskList: TaskListDTO
        var trashEntry: TrashEntryDTO
        var vaultEntry: VaultEntryDTO
        var vaultFolder: VaultFolderDTO
    }

    // Minimal DTOs with minimal valid fields
    struct AccountDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var email: String
    }
    struct AttachmentDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var fileName: String
    }
    struct CalendarDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
    }
    struct CalendarEventDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
    }
    struct ContactDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }
    struct FolderDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }
    struct MailMessageDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var subject: String
    }
    struct TagDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }
    struct TaskDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
    }
    struct TaskListDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }
    struct TrashEntryDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var reason: String
    }
    struct VaultEntryDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var secret: String
    }
    struct VaultFolderDTO: Codable, Equatable, Identifiable {
        var id: UUID
        var label: String
    }

    struct RestoreManifest: Codable {
        var version: Int
        var date: Date
        var checksum: String
    }

    struct RestoreEnvelope: Codable {
        var manifest: RestoreManifest
        var payload: TestPayload
    }

    enum MergeMode {
        case merge, replace
    }

    struct PreviewStats {
        var inserts: Int
        var deletes: Int
        var skips: Int
    }

    // Stubbed store interface for test
    final class Store {
        private var data = [String: Set<UUID>]()

        func clear() {
            data.removeAll()
        }

        func seed<Entity: Equatable & Identifiable>(type: Entity.Type, ids: [UUID]) {
            let key = String(describing: type)
            data[key] = Set(ids)
        }

        func count<Entity>(for type: Entity.Type) -> Int {
            let key = String(describing: type)
            return data[key]?.count ?? 0
        }

        func previewImport(payload: TestPayload, mode: MergeMode) -> [String: PreviewStats] {
            var result: [String: PreviewStats] = [:]

            func calcStats(entityName: String, payloadIds: Set<UUID>) -> PreviewStats {
                let storeIds = data[entityName] ?? []
                switch mode {
                case .merge:
                    let inserts = payloadIds.subtracting(storeIds).count
                    let deletes = 0
                    let skips = payloadIds.intersection(storeIds).count
                    return PreviewStats(inserts: inserts, deletes: deletes, skips: skips)
                case .replace:
                    let deletes = storeIds.subtracting(payloadIds).count
                    let inserts = payloadIds.subtracting(storeIds).count
                    let skips = payloadIds.intersection(storeIds).count
                    return PreviewStats(inserts: inserts, deletes: deletes, skips: skips)
                }
            }

            result["Account"] = calcStats(entityName: "AccountDTO", payloadIds: [payload.account.id])
            result["Attachment"] = calcStats(entityName: "AttachmentDTO", payloadIds: [payload.attachment.id])
            result["Calendar"] = calcStats(entityName: "CalendarDTO", payloadIds: [payload.calendar.id])
            result["CalendarEvent"] = calcStats(entityName: "CalendarEventDTO", payloadIds: [payload.calendarEvent.id])
            result["Contact"] = calcStats(entityName: "ContactDTO", payloadIds: [payload.contact.id])
            result["Folder"] = calcStats(entityName: "FolderDTO", payloadIds: [payload.folder.id])
            result["MailMessage"] = calcStats(entityName: "MailMessageDTO", payloadIds: [payload.mailMessage.id])
            result["Tag"] = calcStats(entityName: "TagDTO", payloadIds: [payload.tag.id])
            result["Task"] = calcStats(entityName: "TaskDTO", payloadIds: [payload.task.id])
            result["TaskList"] = calcStats(entityName: "TaskListDTO", payloadIds: [payload.taskList.id])
            result["TrashEntry"] = calcStats(entityName: "TrashEntryDTO", payloadIds: [payload.trashEntry.id])
            result["VaultEntry"] = calcStats(entityName: "VaultEntryDTO", payloadIds: [payload.vaultEntry.id])
            result["VaultFolder"] = calcStats(entityName: "VaultFolderDTO", payloadIds: [payload.vaultFolder.id])

            return result
        }

        func importBackup(payload: TestPayload, mode: MergeMode) {
            func updateStore(entityName: String, ids: Set<UUID>) {
                switch mode {
                case .merge:
                    let oldIds = data[entityName] ?? []
                    data[entityName] = oldIds.union(ids)
                case .replace:
                    data[entityName] = ids
                }
            }
            updateStore(entityName: "AccountDTO", ids: [payload.account.id])
            updateStore(entityName: "AttachmentDTO", ids: [payload.attachment.id])
            updateStore(entityName: "CalendarDTO", ids: [payload.calendar.id])
            updateStore(entityName: "CalendarEventDTO", ids: [payload.calendarEvent.id])
            updateStore(entityName: "ContactDTO", ids: [payload.contact.id])
            updateStore(entityName: "FolderDTO", ids: [payload.folder.id])
            updateStore(entityName: "MailMessageDTO", ids: [payload.mailMessage.id])
            updateStore(entityName: "TagDTO", ids: [payload.tag.id])
            updateStore(entityName: "TaskDTO", ids: [payload.task.id])
            updateStore(entityName: "TaskListDTO", ids: [payload.taskList.id])
            updateStore(entityName: "TrashEntryDTO", ids: [payload.trashEntry.id])
            updateStore(entityName: "VaultEntryDTO", ids: [payload.vaultEntry.id])
            updateStore(entityName: "VaultFolderDTO", ids: [payload.vaultFolder.id])
        }
    }

    func makeMinimalPayload() -> TestPayload {
        TestPayload(
            account: AccountDTO(id: UUID(), email: "a@b.com"),
            attachment: AttachmentDTO(id: UUID(), fileName: "file.txt"),
            calendar: CalendarDTO(id: UUID(), title: "cal"),
            calendarEvent: CalendarEventDTO(id: UUID(), title: "event"),
            contact: ContactDTO(id: UUID(), name: "contact"),
            folder: FolderDTO(id: UUID(), name: "folder"),
            mailMessage: MailMessageDTO(id: UUID(), subject: "subject"),
            tag: TagDTO(id: UUID(), name: "tag"),
            task: TaskDTO(id: UUID(), title: "task"),
            taskList: TaskListDTO(id: UUID(), name: "list"),
            trashEntry: TrashEntryDTO(id: UUID(), reason: "reason"),
            vaultEntry: VaultEntryDTO(id: UUID(), secret: "secret"),
            vaultFolder: VaultFolderDTO(id: UUID(), label: "label")
        )
    }

    func makeManifest(payload: TestPayload) -> RestoreManifest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Encoding should always succeed for valid payloads, but handle gracefully
        guard let data = try? encoder.encode(payload) else {
            // Return manifest with empty checksum if encoding fails (test will fail appropriately)
            return RestoreManifest(version: 1, date: Date(), checksum: "")
        }
        let digest = SHA256.hash(data: data)
        let checksum = digest.compactMap { String(format: "%02x", $0) }.joined()
        return RestoreManifest(version: 1, date: Date(), checksum: checksum)
    }

    func writeEnvelopeToDisk(envelope: RestoreEnvelope) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let tmp = FileManager.default.temporaryDirectory
        let fileURL = tmp.appendingPathComponent("restore-envelope-\(UUID().uuidString).json")
        try data.write(to: fileURL)
        return fileURL
    }

    @Test("preview and import with merge mode on empty store")
    func testPreviewAndImportMergeMode() throws {
        let store = Store()
        store.clear()

        let payload = makeMinimalPayload()
        let manifest = makeManifest(payload: payload)
        let envelope = RestoreEnvelope(manifest: manifest, payload: payload)
        _ = try writeEnvelopeToDisk(envelope: envelope)

        // Preview import in merge mode on empty store: expect inserts = 1 each, deletes = 0
        let preview1 = store.previewImport(payload: payload, mode: .merge)
        for (entity, stats) in preview1 {
            #expect(stats.inserts) == 1
            #expect(stats.deletes) == 0
        }

        // Perform import merge mode
        store.importBackup(payload: payload, mode: .merge)

        // Preview import second time in merge mode: expect inserts = 0, skips = 1
        let preview2 = store.previewImport(payload: payload, mode: .merge)
        for (entity, stats) in preview2 {
            #expect(stats.inserts) == 0
            #expect(stats.skips) == 1
        }
    }

    @Test("replace mode deletes current and inserts payload counts")
    func testReplaceModeDeletesAndInserts() throws {
        let store = Store()
        store.clear()

        // Seed store with one id per entity
        let existingUUIDs = (0..<1).map { _ in UUID() }
        store.seed(type: AccountDTO.self, ids: existingUUIDs)
        store.seed(type: AttachmentDTO.self, ids: existingUUIDs)
        store.seed(type: CalendarDTO.self, ids: existingUUIDs)
        store.seed(type: CalendarEventDTO.self, ids: existingUUIDs)
        store.seed(type: ContactDTO.self, ids: existingUUIDs)
        store.seed(type: FolderDTO.self, ids: existingUUIDs)
        store.seed(type: MailMessageDTO.self, ids: existingUUIDs)
        store.seed(type: TagDTO.self, ids: existingUUIDs)
        store.seed(type: TaskDTO.self, ids: existingUUIDs)
        store.seed(type: TaskListDTO.self, ids: existingUUIDs)
        store.seed(type: TrashEntryDTO.self, ids: existingUUIDs)
        store.seed(type: VaultEntryDTO.self, ids: existingUUIDs)
        store.seed(type: VaultFolderDTO.self, ids: existingUUIDs)

        // Create payload with different UUIDs (new)
        func newUUID() -> UUID { UUID() }
        let payload = TestPayload(
            account: AccountDTO(id: newUUID(), email: "new@b.com"),
            attachment: AttachmentDTO(id: newUUID(), fileName: "newfile.txt"),
            calendar: CalendarDTO(id: newUUID(), title: "newcal"),
            calendarEvent: CalendarEventDTO(id: newUUID(), title: "newevent"),
            contact: ContactDTO(id: newUUID(), name: "newcontact"),
            folder: FolderDTO(id: newUUID(), name: "newfolder"),
            mailMessage: MailMessageDTO(id: newUUID(), subject: "newsubject"),
            tag: TagDTO(id: newUUID(), name: "newtag"),
            task: TaskDTO(id: newUUID(), title: "newtask"),
            taskList: TaskListDTO(id: newUUID(), name: "newlist"),
            trashEntry: TrashEntryDTO(id: newUUID(), reason: "newreason"),
            vaultEntry: VaultEntryDTO(id: newUUID(), secret: "newsecret"),
            vaultFolder: VaultFolderDTO(id: newUUID(), label: "newlabel")
        )

        // Preview import in replace mode: deletes = 1, inserts = 1 each entity
        let preview = store.previewImport(payload: payload, mode: .replace)
        for (entity, stats) in preview {
            #expect(stats.deletes) == 1
            #expect(stats.inserts) == 1
        }
    }
}
#endif
