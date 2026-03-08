// BackupDiffService+AnalysisMethods.swift
// Entity-specific diff analysis methods for comparing backup data against current database

import Foundation
import SwiftData

extension BackupDiffService {

    // swiftlint:disable:next function_body_length
    func analyzeStudentDiff(
        backupStudents: [StudentDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentStudents: [Student]
        do {
            currentStudents = try modelContext.fetch(FetchDescriptor<Student>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current students: \(error)")
            currentStudents = []
        }
        let currentIDs = Set(currentStudents.map { $0.id })
        let backupIDs = Set(backupStudents.map { $0.id })

        // Added (in current but not in backup)
        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentStudents
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: "\($0.firstName) \($0.lastName)",
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
                changes.append(FieldChange(
                    fieldName: "Birthday",
                    oldValue: dto.birthday.formatted(date: .abbreviated, time: .omitted),
                    newValue: current.birthday.formatted(date: .abbreviated, time: .omitted)
                ))
            }

            if !changes.isEmpty {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: current.id,
                    description: "\(current.firstName) \(current.lastName)",
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "Student", added: added, removed: removed, modified: modified)
    }

    // swiftlint:disable:next function_body_length
    func analyzeLessonDiff(
        backupLessons: [LessonDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentLessons: [Lesson]
        do {
            currentLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current lessons: \(error)")
            currentLessons = []
        }
        let currentIDs = Set(currentLessons.map { $0.id })
        let backupIDs = Set(backupLessons.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentLessons
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: $0.name, timestamp: nil
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
                    entityID: current.id,
                    description: current.name,
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "Lesson", added: added, removed: removed, modified: modified)
    }

    func analyzeNoteDiff(
        backupNotes: [NoteDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [Note]
        do {
            current = try modelContext.fetch(FetchDescriptor<Note>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current notes: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupNotes.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: String($0.body.prefix(40)),
                    timestamp: $0.createdAt
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
            if c.body != dto.body {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: c.id,
                    description: String(c.body.prefix(40)),
                    fieldChanges: [FieldChange(
                        fieldName: "Body",
                        oldValue: String(dto.body.prefix(50)) + "...",
                        newValue: String(c.body.prefix(50)) + "..."
                    )]
                ))
            }
        }

        return EntityDiff(entityType: "Note", added: added, removed: removed, modified: modified)
    }

    func analyzeCalendarDiff(
        backupNonSchoolDays: [NonSchoolDayDTO],
        backupOverrides: [SchoolDayOverrideDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentNSD: [NonSchoolDay]
        let currentOvr: [SchoolDayOverride]
        do {
            currentNSD = try modelContext.fetch(FetchDescriptor<NonSchoolDay>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current non-school days: \(error)")
            currentNSD = []
        }
        do {
            currentOvr = try modelContext.fetch(FetchDescriptor<SchoolDayOverride>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current school day overrides: \(error)")
            currentOvr = []
        }

        var added: [EntityChange] = []
        var removed: [EntityChange] = []

        // Non-school days
        let currentNSDIDs = Set(currentNSD.map { $0.id })
        let backupNSDIDs = Set(backupNonSchoolDays.map { $0.id })

        for id in currentNSDIDs.subtracting(backupNSDIDs) {
            if let nsd = currentNSD.first(where: { $0.id == id }) {
                let desc = "Non-School Day: \(nsd.date.formatted(date: .abbreviated, time: .omitted))"
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
        let currentOvrIDs = Set(currentOvr.map { $0.id })
        let backupOvrIDs = Set(backupOverrides.map { $0.id })

        for id in currentOvrIDs.subtracting(backupOvrIDs) {
            if let ovr = currentOvr.first(where: { $0.id == id }) {
                let desc = "Override: \(ovr.date.formatted(date: .abbreviated, time: .omitted))"
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
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [Project]
        do {
            current = try modelContext.fetch(FetchDescriptor<Project>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current projects: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupProjects.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: $0.title,
                    timestamp: $0.createdAt
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

        return EntityDiff(entityType: "Project", added: added, removed: removed, modified: [])
    }

    func analyzeAttendanceDiff(
        backupAttendance: [AttendanceRecordDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [AttendanceRecord]
        do {
            current = try modelContext.fetch(FetchDescriptor<AttendanceRecord>())
        } catch {
            print("Warning [Backup:\(#function)] Failed to fetch current attendance records: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupAttendance.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map {
                let desc = "Attendance \($0.date.formatted(date: .abbreviated, time: .omitted))"
                return EntityChange(id: UUID(), entityID: $0.id, description: desc, timestamp: nil)
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
