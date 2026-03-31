// BackupDiffService+Comparison.swift
// Backup-to-backup comparison methods

import Foundation

extension BackupDiffService {

    func compareStudents(older: [StudentDTO], newer: [StudentDTO]) -> EntityDiff {
        let olderIDs = Set(older.map(\.id))
        let newerIDs = Set(newer.map(\.id))

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: "\($0.firstName) \($0.lastName)", timestamp: $0.updatedAt
                )
            }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: "\($0.firstName) \($0.lastName)", timestamp: $0.updatedAt
                )
            }

        return EntityDiff(entityType: "CDStudent", added: added, removed: removed, modified: [])
    }

    func compareLessons(older: [LessonDTO], newer: [LessonDTO]) -> EntityDiff {
        let olderIDs = Set(older.map(\.id))
        let newerIDs = Set(newer.map(\.id))

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: $0.updatedAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: $0.updatedAt) }

        return EntityDiff(entityType: "CDLesson", added: added, removed: removed, modified: [])
    }

    func compareNotes(older: [NoteDTO], newer: [NoteDTO]) -> EntityDiff {
        let olderIDs = Set(older.map(\.id))
        let newerIDs = Set(newer.map(\.id))

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: String($0.body.prefix(40)), timestamp: $0.updatedAt
                )
            }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map {
                EntityChange(
                    id: UUID(), entityID: $0.id,
                    description: String($0.body.prefix(40)), timestamp: $0.updatedAt
                )
            }

        return EntityDiff(entityType: "CDNote", added: added, removed: removed, modified: [])
    }

    func compareProjects(older: [ProjectDTO], newer: [ProjectDTO]) -> EntityDiff {
        let olderIDs = Set(older.map(\.id))
        let newerIDs = Set(newer.map(\.id))

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        return EntityDiff(entityType: "CDProject", added: added, removed: removed, modified: [])
    }
}
