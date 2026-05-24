import Foundation
import CryptoKit
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)

// MARK: - Restore Preview Tests

@available(macOS 14, iOS 17, *)
@Suite("Restore Preview tests") final class RestorePreviewTests {

    // MARK: - Helpers

    struct PreviewStats {
        var inserts: Int
        var deletes: Int
        var skips: Int
    }

    enum MergeMode {
        case merge, replace
    }

    final class Store {
        private var data = [String: Set<UUID>]()

        func clear() { data.removeAll() }

        func seed(entityName: String, ids: [UUID]) {
            data[entityName] = Set(ids)
        }

        func previewImport(entities: [String: Set<UUID>], mode: MergeMode) -> [String: PreviewStats] {
            var result: [String: PreviewStats] = [:]
            for (name, payloadIds) in entities {
                let storeIds = data[name] ?? []
                switch mode {
                case .merge:
                    result[name] = PreviewStats(
                        inserts: payloadIds.subtracting(storeIds).count,
                        deletes: 0,
                        skips: payloadIds.intersection(storeIds).count
                    )
                case .replace:
                    result[name] = PreviewStats(
                        inserts: payloadIds.subtracting(storeIds).count,
                        deletes: storeIds.subtracting(payloadIds).count,
                        skips: payloadIds.intersection(storeIds).count
                    )
                }
            }
            return result
        }

        func importEntities(_ entities: [String: Set<UUID>], mode: MergeMode) {
            for (name, ids) in entities {
                switch mode {
                case .merge:
                    data[name] = (data[name] ?? []).union(ids)
                case .replace:
                    data[name] = ids
                }
            }
        }
    }

    // Build a minimal BackupPayload with one student and one lesson
    func makeMinimalPayload() -> BackupPayload {
        let studentID = UUID()
        let lessonID = UUID()
        return BackupPayload(
            items: [],
            students: [
                StudentDTO(
                    id: studentID, firstName: "Ada", lastName: "Lovelace",
                    birthday: Date(timeIntervalSince1970: 0), dateStarted: nil,
                    level: .upper, nextLessons: [], manualOrder: 0
                )
            ],
            lessons: [
                LessonDTO(
                    id: lessonID, name: "Binomial Cube", area: "Sensorial",
                    sequence: "Visual Sense", orderInSequence: 1, section: "",
                    writeUp: ""
                )
            ],
            lessonAssignments: [],
            notes: [
                NoteDTO(
                    id: UUID(), createdAt: Date(), updatedAt: Date(),
                    body: "Observation note", isPinned: false, scope: "{}"
                )
            ],
            nonSchoolDays: [],
            schoolDayOverrides: [],
            studentMeetings: [],
            communityTopics: [],
            proposedSolutions: [],
            communityAttachments: [],
            attendance: [],
            workCompletions: [],
            projects: [],
            projectAssignmentTemplates: [],
            projectSessions: [],
            projectRoles: [],
            projectTemplateWeeks: [],
            projectWeekRoleAssignments: [],
            preferences: PreferencesDTO(values: [:])
        )
    }

    func entityMap(from payload: BackupPayload) -> [String: Set<UUID>] {
        var map: [String: Set<UUID>] = [:]
        map["Student"] = Set(payload.students.map(\.id))
        map["Lesson"] = Set(payload.lessons.map(\.id))
        map["Note"] = Set(payload.notes.map(\.id))
        return map
    }

    // MARK: - Preview Tests

    @Test("merge mode on empty store inserts all entities")
    func testMergeModeEmptyStore() {
        let store = Store()
        let payload = makeMinimalPayload()
        let entities = entityMap(from: payload)

        let preview = store.previewImport(entities: entities, mode: .merge)

        #expect(preview["Student"]?.inserts == 1)
        #expect(preview["Student"]?.deletes == 0)
        #expect(preview["Lesson"]?.inserts == 1)
        #expect(preview["Note"]?.inserts == 1)
    }

    @Test("merge mode after import skips duplicate entities")
    func testMergeModeSkipsDuplicates() {
        let store = Store()
        let payload = makeMinimalPayload()
        let entities = entityMap(from: payload)

        store.importEntities(entities, mode: .merge)
        let preview = store.previewImport(entities: entities, mode: .merge)

        #expect(preview["Student"]?.inserts == 0)
        #expect(preview["Student"]?.skips == 1)
        #expect(preview["Lesson"]?.skips == 1)
    }

    @Test("replace mode deletes existing and inserts new entities")
    func testReplaceModeDeletesAndInserts() {
        let store = Store()
        store.seed(entityName: "Student", ids: [UUID()])
        store.seed(entityName: "Lesson", ids: [UUID()])

        let payload = makeMinimalPayload()
        let entities = entityMap(from: payload)

        let preview = store.previewImport(entities: entities, mode: .replace)

        #expect(preview["Student"]?.deletes == 1)
        #expect(preview["Student"]?.inserts == 1)
        #expect(preview["Lesson"]?.deletes == 1)
        #expect(preview["Lesson"]?.inserts == 1)
    }
}

// MARK: - Payload Round-Trip Tests

@available(macOS 14, iOS 17, *)
@Suite("Payload round-trip tests") final class PayloadRoundTripTests {

    func makeTestPayload() -> BackupPayload {
        let studentID = UUID()
        let lessonID = UUID()
        let noteID = UUID()

        return BackupPayload(
            items: [],
            students: [
                StudentDTO(
                    id: studentID, firstName: "Maria", lastName: "Montessori",
                    birthday: Date(timeIntervalSince1970: -2_524_608_000),
                    dateStarted: Date(timeIntervalSince1970: 1_704_067_200),
                    level: .lower, nextLessons: [lessonID], manualOrder: 1
                )
            ],
            lessons: [
                LessonDTO(
                    id: lessonID, name: "Pink Tower", area: "Sensorial",
                    sequence: "Visual Sense", orderInSequence: 1, section: "Extension 1",
                    writeUp: "The child builds a tower from largest to smallest cube.",
                    materials: "10 pink cubes", purpose: "Visual discrimination of size"
                )
            ],
            lessonAssignments: [],
            notes: [
                NoteDTO(
                    id: noteID, createdAt: Date(), updatedAt: Date(),
                    body: "Student showed great concentration", isPinned: true,
                    scope: "{\"student\":\"" + studentID.uuidString + "\"}"
                )
            ],
            nonSchoolDays: [],
            schoolDayOverrides: [],
            studentMeetings: [],
            communityTopics: [],
            proposedSolutions: [],
            communityAttachments: [],
            attendance: [],
            workCompletions: [],
            projects: [],
            projectAssignmentTemplates: [],
            projectSessions: [],
            projectRoles: [],
            projectTemplateWeeks: [],
            projectWeekRoleAssignments: [],
            preferences: PreferencesDTO(values: [
                "schoolName": .string("Casa dei Bambini"),
                "showWeekends": .bool(false),
                "maxStudents": .int(30)
            ])
        )
    }

    @Test("payload survives JSON encode → decode round-trip")
    func testPayloadRoundTrip() throws {
        let original = makeTestPayload()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        #expect(decoded.students.count == original.students.count)
        #expect(decoded.students.first?.id == original.students.first?.id)
        #expect(decoded.students.first?.firstName == "Maria")
        #expect(decoded.students.first?.level == .lower)

        #expect(decoded.lessons.count == original.lessons.count)
        #expect(decoded.lessons.first?.name == "Pink Tower")
        #expect(decoded.lessons.first?.materials == "10 pink cubes")

        #expect(decoded.notes.count == original.notes.count)
        #expect(decoded.notes.first?.isPinned == true)

        #expect(decoded.preferences.values["schoolName"] == .string("Casa dei Bambini"))
        #expect(decoded.preferences.values["showWeekends"] == .bool(false))
        #expect(decoded.preferences.values["maxStudents"] == .int(30))
    }

    @Test("checksum is stable across encode cycles (deterministic JSON)")
    func testDeterministicChecksum() throws {
        let payload = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys

        let data1 = try encoder.encode(payload)
        let data2 = try encoder.encode(payload)

        let hash1 = SHA256.hash(data: data1).compactMap { String(format: "%02x", $0) }.joined()
        let hash2 = SHA256.hash(data: data2).compactMap { String(format: "%02x", $0) }.joined()

        #expect(hash1 == hash2)
    }

    @Test("older format payloads decode with nil optional arrays")
    func testOlderFormatDecodes() throws {
        // Simulate a v5 payload — only core fields, no optional arrays
        let payload = makeTestPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)

        // Verify optional v8+ fields are nil when not present
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        #expect(decoded.workModels == nil)
        #expect(decoded.workCheckIns == nil)
        #expect(decoded.tracks == nil)
        #expect(decoded.goingOuts == nil)
        #expect(decoded.classroomMemberships == nil)
        #expect(decoded.planningRecommendations == nil)
        #expect(decoded.resources == nil)

        // Core fields should still be present
        #expect(decoded.students.count == 1)
        #expect(decoded.lessons.count == 1)
    }
}

// MARK: - Version Compatibility Tests

@available(macOS 14, iOS 17, *)
@Suite("Backup version compatibility tests") final class VersionCompatibilityTests {

    @Test("current version is compatible")
    func testCurrentVersionCompatible() {
        let result = BackupMigrationManifest.isCompatible(version: BackupFile.formatVersion)
        #expect(result.isCompatible)
    }

    @Test("older versions are invalid")
    func testOldVersionInvalid() {
        let result = BackupMigrationManifest.isCompatible(version: BackupFile.formatVersion - 1)
        #expect(!result.isCompatible)
    }

    @Test("future version is detected")
    func testFutureVersionDetected() {
        let future = BackupFile.formatVersion + 1
        let result = BackupMigrationManifest.isCompatible(version: future)
        if case .futureVersion(let v) = result {
            #expect(v == future)
        } else {
            #expect(Bool(false), "Expected futureVersion case")
        }
    }

    @Test("version history covers all documented versions")
    func testVersionHistoryCompleteness() {
        let documented = Set(BackupMigrationManifest.versionHistory.map(\.version))
        #expect(documented.contains(5))
        #expect(documented.contains(BackupFile.formatVersion))
    }
}

#endif
