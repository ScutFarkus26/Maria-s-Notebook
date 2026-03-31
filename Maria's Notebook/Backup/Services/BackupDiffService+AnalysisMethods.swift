// BackupDiffService+AnalysisMethods.swift
// Entity-specific diff analysis methods for comparing backup data against current database

import Foundation
import CoreData
import OSLog

extension BackupDiffService {

    private static let logger = Logger.backup

    // swiftlint:disable:next function_body_length
    func analyzeStudentDiff(
        backupStudents: [StudentDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let currentStudents: [CDStudent]
        do {
            currentStudents = try viewContext.fetch(CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>)
        } catch {
            Self.logger.warning("Failed to fetch current students: \(error.localizedDescription, privacy: .public)")
            currentStudents = []
        }
        let currentIDs = Set(currentStudents.compactMap(\.id))
        let backupIDs = Set(backupStudents.map(\.id))

        // Added (in current but not in backup)
        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentStudents
            .filter { $0.id.map { addedIDs.contains($0) } ?? false }
            .compactMap { s -> EntityChange? in
                guard let entityID = s.id else { return nil }
                return EntityChange(
                    id: UUID(), entityID: entityID,
                    description: "\(s.firstName) \(s.lastName)",
                    timestamp: nil
                )
            }

        // Removed (in backup but not in current)
        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupStudents
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: "\($0.firstName) \($0.lastName)",
                    timestamp: $0.updatedAt
                )
            }

        // Modified (in both but different)
        var modified: [EntityModification] = []
        for dto in backupStudents {
            guard let current = currentStudents.first(
                where: { $0.id == dto.id }
            ) else { continue }
            guard let currentID = current.id else { continue }
            var changes: [FieldChange] = []

            if current.firstName != dto.firstName {
                changes.append(FieldChange(
                    fieldName: "First Name", oldValue: dto.firstName, newValue: current.firstName
                ))
            }
            if current.lastName != dto.lastName {
                changes.append(FieldChange(fieldName: "Last Name", oldValue: dto.lastName, newValue: current.lastName))
            }
            if current.birthday != dto.birthday {
                let currentBday = current.birthday?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                changes.append(FieldChange(
                    fieldName: "Birthday",
                    oldValue: dto.birthday.formatted(date: .abbreviated, time: .omitted),
                    newValue: currentBday
                ))
            }

            if !changes.isEmpty {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: currentID,
                    description: "\(current.firstName) \(current.lastName)",
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "CDStudent", added: added, removed: removed, modified: modified)
    }

    // swiftlint:disable:next function_body_length
    func analyzeLessonDiff(
        backupLessons: [LessonDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let currentLessons: [CDLesson]
        do {
            currentLessons = try viewContext.fetch(CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>)
        } catch {
            Self.logger.warning("Failed to fetch current lessons: \(error.localizedDescription, privacy: .public)")
            currentLessons = []
        }
        let currentIDs = Set(currentLessons.compactMap(\.id))
        let backupIDs = Set(backupLessons.map(\.id))

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentLessons
            .filter { $0.id.map { addedIDs.contains($0) } ?? false }
            .compactMap { l -> EntityChange? in
                guard let entityID = l.id else { return nil }
                return EntityChange(
                    id: UUID(), entityID: entityID,
                    description: l.name, timestamp: nil
                )
            }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupLessons
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: $0.name,
                    timestamp: $0.updatedAt
                )
            }

        var modified: [EntityModification] = []
        for dto in backupLessons {
            guard let current = currentLessons.first(where: { $0.id == dto.id }) else { continue }
            guard let currentID = current.id else { continue }
            var changes: [FieldChange] = []

            if current.name != dto.name {
                changes.append(FieldChange(fieldName: "Name", oldValue: dto.name, newValue: current.name))
            }
            if current.subject != dto.subject {
                changes.append(FieldChange(fieldName: "Subject", oldValue: dto.subject, newValue: current.subject))
            }
            if current.writeUp != dto.writeUp {
                changes.append(FieldChange(
                    fieldName: "Write-up",
                    oldValue: String(dto.writeUp.prefix(50)) + "...",
                    newValue: String(current.writeUp.prefix(50)) + "..."
                ))
            }

            if !changes.isEmpty {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: currentID,
                    description: current.name,
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "CDLesson", added: added, removed: removed, modified: modified)
    }

    func analyzeNoteDiff(
        backupNotes: [NoteDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let current: [CDNote]
        do {
            current = try viewContext.fetch(CDNote.fetchRequest() as! NSFetchRequest<CDNote>)
        } catch {
            Self.logger.warning("Failed to fetch current notes: \(error.localizedDescription, privacy: .public)")
            current = []
        }
        let currentIDs = Set(current.compactMap(\.id))
        let backupIDs = Set(backupNotes.map(\.id))

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { $0.id.map { addedIDs.contains($0) } ?? false }
            .compactMap { n -> EntityChange? in
                guard let entityID = n.id else { return nil }
                return EntityChange(
                    id: UUID(), entityID: entityID,
                    description: String(n.body.prefix(40)),
                    timestamp: n.createdAt
                )
            }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupNotes
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: String($0.body.prefix(40)),
                    timestamp: $0.createdAt
                )
            }

        var modified: [EntityModification] = []
        for dto in backupNotes {
            guard let c = current.first(where: { $0.id == dto.id }) else { continue }
            guard let cID = c.id else { continue }
            if c.body != dto.body {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: cID,
                    description: String(c.body.prefix(40)),
                    fieldChanges: [FieldChange(
                        fieldName: "Body",
                        oldValue: String(dto.body.prefix(50)) + "...",
                        newValue: String(c.body.prefix(50)) + "..."
                    )]
                ))
            }
        }

        return EntityDiff(entityType: "CDNote", added: added, removed: removed, modified: modified)
    }

    func analyzeCalendarDiff(
        backupNonSchoolDays: [NonSchoolDayDTO],
        backupOverrides: [SchoolDayOverrideDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let currentNSD: [CDNonSchoolDay]
        let currentOvr: [CDSchoolDayOverride]
        do {
            currentNSD = try viewContext.fetch(CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to fetch current non-school days: \(desc, privacy: .public)")
            currentNSD = []
        }
        do {
            currentOvr = try viewContext.fetch(CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to fetch current school day overrides: \(desc, privacy: .public)")
            currentOvr = []
        }

        var added: [EntityChange] = []
        var removed: [EntityChange] = []

        // Non-school days
        let currentNSDIDs = Set(currentNSD.compactMap(\.id))
        let backupNSDIDs = Set(backupNonSchoolDays.map(\.id))

        for id in currentNSDIDs.subtracting(backupNSDIDs) {
            if let nsd = currentNSD.first(where: { $0.id == id }) {
                let dateStr = nsd.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                let desc = "Non-School Day: \(dateStr)"
                added.append(EntityChange(id: UUID(), entityID: id, description: desc, timestamp: nil))
            }
        }
        for id in backupNSDIDs.subtracting(currentNSDIDs) {
            if let nsd = backupNonSchoolDays.first(where: { $0.id == id }) {
                let desc = "Non-School Day: \(nsd.date.formatted(date: .abbreviated, time: .omitted))"
                removed.append(EntityChange(id: UUID(), entityID: id, description: desc, timestamp: nil))
            }
        }

        // School day overrides
        let currentOvrIDs = Set(currentOvr.compactMap(\.id))
        let backupOvrIDs = Set(backupOverrides.map(\.id))

        for id in currentOvrIDs.subtracting(backupOvrIDs) {
            if let ovr = currentOvr.first(where: { $0.id == id }) {
                let dateStr = ovr.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                let desc = "Override: \(dateStr)"
                added.append(EntityChange(id: UUID(), entityID: id, description: desc, timestamp: nil))
            }
        }
        for id in backupOvrIDs.subtracting(currentOvrIDs) {
            if let ovr = backupOverrides.first(where: { $0.id == id }) {
                let desc = "Override: \(ovr.date.formatted(date: .abbreviated, time: .omitted))"
                removed.append(EntityChange(id: UUID(), entityID: id, description: desc, timestamp: nil))
            }
        }

        return EntityDiff(entityType: "Calendar", added: added, removed: removed, modified: [])
    }

    func analyzeProjectDiff(
        backupProjects: [ProjectDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let current: [CDProject]
        do {
            current = try viewContext.fetch(CDProject.fetchRequest() as! NSFetchRequest<CDProject>)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to fetch current projects: \(desc, privacy: .public)")
            current = []
        }
        let currentIDs = Set(current.compactMap(\.id))
        let backupIDs = Set(backupProjects.map(\.id))

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { $0.id.map { addedIDs.contains($0) } ?? false }
            .compactMap { p -> EntityChange? in
                guard let entityID = p.id else { return nil }
                return EntityChange(
                    id: UUID(), entityID: entityID,
                    description: p.title,
                    timestamp: p.createdAt
                )
            }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupProjects
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: $0.title,
                    timestamp: $0.createdAt
                )
            }

        return EntityDiff(entityType: "CDProject", added: added, removed: removed, modified: [])
    }

    func analyzeAttendanceDiff(
        backupAttendance: [AttendanceRecordDTO],
        viewContext: NSManagedObjectContext
    ) -> EntityDiff {
        let current: [CDAttendanceRecord]
        do {
            current = try viewContext.fetch(CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to fetch current attendance records: \(desc, privacy: .public)")
            current = []
        }
        let currentIDs = Set(current.compactMap(\.id))
        let backupIDs = Set(backupAttendance.map(\.id))

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { $0.id.map { addedIDs.contains($0) } ?? false }
            .compactMap { a -> EntityChange? in
                guard let entityID = a.id else { return nil }
                let dateStr = a.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                let desc = "Attendance \(dateStr)"
                return EntityChange(id: UUID(), entityID: entityID, description: desc, timestamp: nil)
            }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupAttendance
            .filter { removedIDs.contains($0.id) }
            .map {
                let desc = "Attendance \($0.date.formatted(date: .abbreviated, time: .omitted))"
                return EntityChange(id: UUID(), entityID: $0.id, description: desc, timestamp: nil)
            }

        return EntityDiff(entityType: "Attendance", added: added, removed: removed, modified: [])
    }
}
