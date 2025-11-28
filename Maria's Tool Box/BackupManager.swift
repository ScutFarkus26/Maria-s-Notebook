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
    var lessons: [LessonDTO]

    private enum CodingKeys: String, CodingKey {
        case version, createdAt, items, students, lessons
    }

    init(version: Int, createdAt: Date, items: [ItemDTO], students: [StudentDTO], lessons: [LessonDTO]) {
        self.version = version
        self.createdAt = createdAt
        self.items = items
        self.students = students
        self.lessons = lessons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.items = try container.decode([ItemDTO].self, forKey: .items)
        self.students = try container.decode([StudentDTO].self, forKey: .students)
        // Default to empty if missing (backward compatibility with v1 backups)
        self.lessons = try container.decodeIfPresent([LessonDTO].self, forKey: .lessons) ?? []
    }
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

struct LessonDTO: Codable {
    var id: UUID
    var name: String
    var subject: String
    var group: String
    var subheading: String
    var writeUp: String
}

// MARK: - Backup Manager

enum BackupManager {
    /// Current backup format version. Bump if you change the payload shape.
    static let currentVersion: Int = 2

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

        // Fetch all Lessons
        let lessonsFetch = FetchDescriptor<Lesson>()
        let lessons = try context.fetch(lessonsFetch)
        let lessonsDTO: [LessonDTO] = lessons.map { l in
            LessonDTO(
                id: l.id,
                name: l.name,
                subject: l.subject,
                group: l.group,
                subheading: l.subheading,
                writeUp: l.writeUp
            )
        }

        let payload = BackupPayload(
            version: currentVersion,
            createdAt: Date(),
            items: itemsDTO,
            students: studentsDTO,
            lessons: lessonsDTO
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Import JSON backup data into the database, replacing existing content.
    /// - Note: This will delete all existing Items, Lessons and Students before inserting from backup.
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

        // Insert Lessons (preserving IDs)
        for dto in payload.lessons {
            let lesson = Lesson(
                id: dto.id,
                name: dto.name,
                subject: dto.subject,
                group: dto.group,
                subheading: dto.subheading,
                writeUp: dto.writeUp
            )
            context.insert(lesson)
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

    /// Delete all Items, Lessons, and Students from the store.
    static func deleteAll(using context: ModelContext) throws {
        // Delete Items
        do {
            let items = try context.fetch(FetchDescriptor<Item>())
            for obj in items { context.delete(obj) }
        }
        // Delete Lessons
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            for obj in lessons { context.delete(obj) }
        }
        // Delete Students
        do {
            let students = try context.fetch(FetchDescriptor<Student>())
            for obj in students { context.delete(obj) }
        }
        try context.save()
    }
}
