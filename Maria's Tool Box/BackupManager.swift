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
    var studentLessons: [StudentLessonDTO]
    var subjectOrder: [String]
    var groupOrders: [String: [String]]

    private enum CodingKeys: String, CodingKey {
        case version, createdAt, items, students, lessons, studentLessons, subjectOrder, groupOrders
    }

    init(version: Int, createdAt: Date, items: [ItemDTO], students: [StudentDTO], lessons: [LessonDTO], studentLessons: [StudentLessonDTO], subjectOrder: [String], groupOrders: [String: [String]]) {
        self.version = version
        self.createdAt = createdAt
        self.items = items
        self.students = students
        self.lessons = lessons
        self.studentLessons = studentLessons
        self.subjectOrder = subjectOrder
        self.groupOrders = groupOrders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.items = try container.decode([ItemDTO].self, forKey: .items)
        self.students = try container.decode([StudentDTO].self, forKey: .students)
        self.lessons = try container.decodeIfPresent([LessonDTO].self, forKey: .lessons) ?? []
        self.studentLessons = try container.decodeIfPresent([StudentLessonDTO].self, forKey: .studentLessons) ?? []
        self.subjectOrder = try container.decodeIfPresent([String].self, forKey: .subjectOrder) ?? []
        self.groupOrders = try container.decodeIfPresent([String: [String]].self, forKey: .groupOrders) ?? [:]
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
    var orderInGroup: Int
    var subheading: String
    var writeUp: String

    private enum CodingKeys: String, CodingKey {
        case id, name, subject, group, orderInGroup, subheading, writeUp
    }

    init(id: UUID, name: String, subject: String, group: String, orderInGroup: Int, subheading: String, writeUp: String) {
        self.id = id
        self.name = name
        self.subject = subject
        self.group = group
        self.orderInGroup = orderInGroup
        self.subheading = subheading
        self.writeUp = writeUp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.subject = try container.decode(String.self, forKey: .subject)
        self.group = try container.decode(String.self, forKey: .group)
        self.orderInGroup = try container.decodeIfPresent(Int.self, forKey: .orderInGroup) ?? 0
        self.subheading = try container.decode(String.self, forKey: .subheading)
        self.writeUp = try container.decode(String.self, forKey: .writeUp)
    }
}

struct StudentLessonDTO: Codable {
    var id: UUID
    var lessonID: UUID
    var studentIDs: [UUID]
    var createdAt: Date
    var scheduledFor: Date?
    var givenAt: Date?
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String
}

// MARK: - Backup Manager

enum BackupManager {
    /// Current backup format version. Bump if you change the payload shape.
    static let currentVersion: Int = 4

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
                orderInGroup: l.orderInGroup,
                subheading: l.subheading,
                writeUp: l.writeUp
            )
        }
        
        // Fetch all StudentLessons
        let slFetch = FetchDescriptor<StudentLesson>()
        let sls = try context.fetch(slFetch)
        let studentLessonsDTO: [StudentLessonDTO] = sls.map { sl in
            StudentLessonDTO(
                id: sl.id,
                lessonID: sl.lessonID,
                studentIDs: sl.studentIDs,
                createdAt: sl.createdAt,
                scheduledFor: sl.scheduledFor,
                givenAt: sl.givenAt,
                notes: sl.notes,
                needsPractice: sl.needsPractice,
                needsAnotherPresentation: sl.needsAnotherPresentation,
                followUpWork: sl.followUpWork
            )
        }

        // Compute subjects and per-subject group orders from current data and saved preferences
        let existingSubjects: [String] = Array(Set(lessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let subjectOrder: [String] = FilterOrderStore.loadSubjectOrder(existing: existingSubjects)

        func groups(for subject: String) -> [String] {
            let gs = lessons
                .filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
                .map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(gs)).sorted()
        }

        var groupOrders: [String: [String]] = [:]
        for subject in subjectOrder {
            let existingGroups = groups(for: subject)
            let order = FilterOrderStore.loadGroupOrder(for: subject, existing: existingGroups)
            if !order.isEmpty { groupOrders[subject] = order }
        }

        let payload = BackupPayload(
            version: currentVersion,
            createdAt: Date(),
            items: itemsDTO,
            students: studentsDTO,
            lessons: lessonsDTO,
            studentLessons: studentLessonsDTO,
            subjectOrder: subjectOrder,
            groupOrders: groupOrders
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
            lesson.orderInGroup = dto.orderInGroup
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

        // Insert StudentLessons (preserving IDs)
        for dto in payload.studentLessons {
            let sl = StudentLesson(
                id: dto.id,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs,
                createdAt: dto.createdAt,
                scheduledFor: dto.scheduledFor,
                givenAt: dto.givenAt,
                notes: dto.notes,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork
            )
            context.insert(sl)
        }
        
        // Backward compatibility: synthesize unscheduled StudentLesson records if missing but nextLessons present
        if payload.studentLessons.isEmpty {
            let existingLessonIDs = Set(try context.fetch(FetchDescriptor<Lesson>()).map { $0.id })
            let studentMap = try context.fetch(FetchDescriptor<Student>()).reduce(into: [UUID: Student]()) { $0[$1.id] = $1 }
            for sDTO in payload.students where !sDTO.nextLessons.isEmpty {
                guard let student = studentMap[sDTO.id] else { continue }
                for lID in sDTO.nextLessons where existingLessonIDs.contains(lID) {
                    let sl = StudentLesson(
                        lessonID: lID,
                        studentIDs: [student.id],
                        createdAt: payload.createdAt,
                        scheduledFor: nil,
                        givenAt: nil,
                        notes: "",
                        needsPractice: false,
                        needsAnotherPresentation: false,
                        followUpWork: ""
                    )
                    context.insert(sl)
                }
            }
        }

        // Restore subject and group ordering preferences if present
        if !payload.subjectOrder.isEmpty {
            FilterOrderStore.saveSubjectOrder(payload.subjectOrder)
        }
        if !payload.groupOrders.isEmpty {
            for (subject, order) in payload.groupOrders {
                FilterOrderStore.saveGroupOrder(order, for: subject)
            }
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
        // Delete StudentLessons
        do {
            let sls = try context.fetch(FetchDescriptor<StudentLesson>())
            for obj in sls { context.delete(obj) }
        }
        try context.save()
    }
}
