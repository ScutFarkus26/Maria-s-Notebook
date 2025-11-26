// BackupManager.swift
// Maria's Toolbox
//
// Provides JSON export/import for SwiftData models.

import Foundation
import SwiftData

// MARK: - Backup payload DTOs

struct BackupPayload: Codable {
    var version: Int
    var createdAt: Date
    var items: [ItemDTO]
    var students: [StudentDTO]
}

struct ItemDTO: Codable {
    var id: UUID
    var timestamp: Date
}

struct StudentDTO: Codable {
    enum Level: String, Codable, CaseIterable {
        case lower = "Lower"
        case upper = "Upper"
    }
    var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date
    var level: Level
    var nextLessons: [UUID]
    var manualOrder: Int
}

// MARK: - Backup Manager

enum BackupManager {
    /// Current backup format version. Bump if you change the payload shape.
    static let currentVersion: Int = 1

    /// Create JSON data representing the current database state.
    static func makeBackupData(using context: ModelContext) throws -> Data {
        // Fetch all Items
        let itemsFetch = FetchDescriptor<Item>()
        let items = try context.fetch(itemsFetch)
        let itemsDTO: [ItemDTO] = items.map { item in
            // Item has no id in the model; synthesize a stable one from timestamp+UUID? We'll use mirror via objectID not available.
            // Instead, embed a generated UUID per export. Since Item has no id property, we cannot preserve identity across restore.
            // We'll assign new IDs on import for Item; keep a transient id here.
            ItemDTO(id: UUID(), timestamp: item.timestamp)
        }

        // Fetch all Students
        let studentsFetch = FetchDescriptor<Student>()
        let students = try context.fetch(studentsFetch)
        let studentsDTO: [StudentDTO] = students.map { s in
            StudentDTO(
                id: s.id,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                level: StudentDTO.Level(rawValue: s.level.rawValue) ?? .lower,
                nextLessons: s.nextLessons,
                manualOrder: s.manualOrder
            )
        }

        let payload = BackupPayload(
            version: currentVersion,
            createdAt: Date(),
            items: itemsDTO,
            students: studentsDTO
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Import JSON backup data into the database, replacing existing content.
    /// - Note: This will delete all existing Items and Students before inserting from backup.
    static func restore(from data: Data, using context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        // Optionally validate version
        guard payload.version <= currentVersion else {
            throw NSError(domain: "BackupManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup file was created by a newer app version."])
        }

        // Delete existing data first
        try deleteAll(using: context)

        // Insert Items
        for dto in payload.items {
            let newItem = Item(timestamp: dto.timestamp)
            context.insert(newItem)
        }

        // Insert Students (preserving IDs)
        for dto in payload.students {
            let level: Student.Level = (dto.level == .upper) ? .upper : .lower
            let student = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: level,
                nextLessons: dto.nextLessons,
                manualOrder: dto.manualOrder
            )
            context.insert(student)
        }

        try context.save()
    }

    /// Delete all Items and Students from the store.
    static func deleteAll(using context: ModelContext) throws {
        // Delete Items
        do {
            let items = try context.fetch(FetchDescriptor<Item>())
            for obj in items { context.delete(obj) }
        }
        // Delete Students
        do {
            let students = try context.fetch(FetchDescriptor<Student>())
            for obj in students { context.delete(obj) }
        }
        try context.save()
    }
}
