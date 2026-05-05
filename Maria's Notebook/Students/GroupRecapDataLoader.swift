// GroupRecapDataLoader.swift
// Bulk Core Data fetches + indexing + note distribution used by
// GroupRecapResolver. Splitting these out keeps the resolver focused on
// snapshot building.

import Foundation
import CoreData

// MARK: - Loader

enum GroupRecapDataLoader {

    @MainActor
    static func collect(
        lessonIDs: [String],
        studentIDs: [String],
        context: NSManagedObjectContext
    ) -> GroupRecapCollectedData {
        let assignments = fetchAssignments(lessonIDs: lessonIDs, context: context)
        let presentations = fetchPresentations(
            lessonIDs: lessonIDs,
            studentIDs: studentIDs,
            context: context
        )
        let work = fetchWork(lessonIDs: lessonIDs, studentIDs: studentIDs, context: context)
        let notes = fetchLessonScopedNotes(lessonIDs: lessonIDs, context: context)
        let studentLinks = fetchStudentLinks(
            noteIDs: notes.compactMap { $0.id?.uuidString },
            context: context
        )
        return GroupRecapCollectedData(
            assignmentsByLesson: Dictionary(grouping: assignments) { $0.lessonID },
            presentationByPair: indexPresentations(presentations),
            workByPair: indexWork(work),
            notes: notes,
            studentLinks: studentLinks
        )
    }

    // MARK: - Fetches

    @MainActor
    static func fetchLessonsInGroup(
        group: String,
        subject: String,
        context: NSManagedObjectContext
    ) -> [CDLesson] {
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(
            format: "group ==[c] %@ AND subject ==[c] %@ AND group != %@",
            group, subject, ""
        )
        req.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.orderInGroup, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)
        ]
        return context.safeFetch(req)
    }

    @MainActor
    private static func fetchAssignments(
        lessonIDs: [String],
        context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        guard !lessonIDs.isEmpty else { return [] }
        let req = CDFetchRequest(CDLessonAssignment.self)
        req.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        return context.safeFetch(req)
    }

    @MainActor
    private static func fetchPresentations(
        lessonIDs: [String],
        studentIDs: [String],
        context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        guard !lessonIDs.isEmpty, !studentIDs.isEmpty else { return [] }
        let req = CDFetchRequest(CDLessonPresentation.self)
        req.predicate = NSPredicate(
            format: "lessonID IN %@ AND studentID IN %@",
            lessonIDs, studentIDs
        )
        return context.safeFetch(req)
    }

    @MainActor
    private static func fetchWork(
        lessonIDs: [String],
        studentIDs: [String],
        context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        guard !lessonIDs.isEmpty, !studentIDs.isEmpty else { return [] }
        let req = CDFetchRequest(CDWorkModel.self)
        req.predicate = NSPredicate(
            format: "lessonID IN %@ AND studentID IN %@",
            lessonIDs, studentIDs
        )
        return context.safeFetch(req)
    }

    @MainActor
    private static func fetchLessonScopedNotes(
        lessonIDs: [String],
        context: NSManagedObjectContext
    ) -> [CDNote] {
        guard !lessonIDs.isEmpty else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        return context.safeFetch(req)
    }

    @MainActor
    private static func fetchStudentLinks(
        noteIDs: [String],
        context: NSManagedObjectContext
    ) -> [String: Set<String>] {
        guard !noteIDs.isEmpty else { return [:] }
        let req = CDFetchRequest(CDNoteStudentLink.self)
        req.predicate = NSPredicate(format: "noteID IN %@", noteIDs)
        let links = context.safeFetch(req)
        var byNote: [String: Set<String>] = [:]
        for link in links {
            byNote[link.noteID, default: []].insert(link.studentID)
        }
        return byNote
    }

    // MARK: - Indexing

    private static func indexPresentations(
        _ presentations: [CDLessonPresentation]
    ) -> [GroupRecapPairKey: CDLessonPresentation] {
        var byPair: [GroupRecapPairKey: CDLessonPresentation] = [:]
        for p in presentations {
            let key = GroupRecapPairKey(lessonID: p.lessonID, studentID: p.studentID)
            if let existing = byPair[key] {
                let new = (p.lastObservedAt ?? p.presentedAt ?? .distantPast)
                let old = (existing.lastObservedAt ?? existing.presentedAt ?? .distantPast)
                if new > old { byPair[key] = p }
            } else {
                byPair[key] = p
            }
        }
        return byPair
    }

    private static func indexWork(
        _ work: [CDWorkModel]
    ) -> [GroupRecapPairKey: [CDWorkModel]] {
        work.reduce(into: [:]) { dict, w in
            let key = GroupRecapPairKey(lessonID: w.lessonID, studentID: w.studentID)
            dict[key, default: []].append(w)
        }
    }
}

// MARK: - Note Bucketer

/// Distributes lesson-scoped CDNote rows into the most-specific bucket each
/// belongs to (check-in > work > assignment > direct lesson > orphan).
enum GroupRecapNoteBucketer {

    static func bucket(
        notes: [CDNote],
        studentLinks: [String: Set<String>],
        studentIDSet: Set<String>,
        lessonIDSet: Set<String>
    ) -> GroupRecapNoteBuckets {
        var byCheckIn: [String: [CDNote]] = [:]
        var byWork: [String: [CDNote]] = [:]
        var byAssignment: [String: [CDNote]] = [:]
        var directByPair: [GroupRecapPairKey: [CDNote]] = [:]
        var orphanByStudent: [String: [CDNote]] = [:]

        for note in notes {
            let effective = resolveStudents(
                for: note,
                links: studentLinks,
                studentIDSet: studentIDSet
            )
            guard !effective.isEmpty else { continue }

            if assign(note: note, byCheckIn: &byCheckIn) { continue }
            if assign(note: note, byWork: &byWork) { continue }
            if assign(note: note, byAssignment: &byAssignment) { continue }

            if let lid = note.lessonID, lessonIDSet.contains(lid) {
                for sid in effective {
                    let key = GroupRecapPairKey(lessonID: lid, studentID: sid)
                    directByPair[key, default: []].append(note)
                }
                continue
            }
            for sid in effective {
                orphanByStudent[sid, default: []].append(note)
            }
        }

        return GroupRecapNoteBuckets(
            notesByCheckIn: byCheckIn,
            notesByWork: byWork,
            notesByAssignment: byAssignment,
            directNotesByPair: directByPair,
            orphanNotesByStudent: orphanByStudent
        )
    }

    private static func assign(note: CDNote, byCheckIn: inout [String: [CDNote]]) -> Bool {
        guard let cid = note.workCheckIn?.id?.uuidString else { return false }
        byCheckIn[cid, default: []].append(note)
        return true
    }

    private static func assign(note: CDNote, byWork: inout [String: [CDNote]]) -> Bool {
        guard let wid = note.work?.id?.uuidString else { return false }
        byWork[wid, default: []].append(note)
        return true
    }

    private static func assign(note: CDNote, byAssignment: inout [String: [CDNote]]) -> Bool {
        guard let aid = note.lessonAssignment?.id?.uuidString else { return false }
        byAssignment[aid, default: []].append(note)
        return true
    }

    private static func resolveStudents(
        for note: CDNote,
        links: [String: Set<String>],
        studentIDSet: Set<String>
    ) -> Set<String> {
        if note.scopeIsAll { return studentIDSet }
        if let nid = note.id?.uuidString,
           let linked = links[nid]?.intersection(studentIDSet),
           !linked.isEmpty {
            return linked
        }
        if let single = note.searchIndexStudentID?.uuidString,
           studentIDSet.contains(single) {
            return [single]
        }
        return []
    }
}

// MARK: - Internal Types

/// Result of bulk Core Data fetches, with everything pre-indexed for O(1) per-pair lookup.
struct GroupRecapCollectedData {
    let assignmentsByLesson: [String: [CDLessonAssignment]]
    let presentationByPair: [GroupRecapPairKey: CDLessonPresentation]
    let workByPair: [GroupRecapPairKey: [CDWorkModel]]
    let notes: [CDNote]
    let studentLinks: [String: Set<String>]
}

/// Notes distributed into their target buckets. Each note appears in exactly one
/// bucket (most specific wins), guaranteeing it shows up exactly once in the UI.
struct GroupRecapNoteBuckets {
    let notesByCheckIn: [String: [CDNote]]
    let notesByWork: [String: [CDNote]]
    let notesByAssignment: [String: [CDNote]]
    let directNotesByPair: [GroupRecapPairKey: [CDNote]]
    let orphanNotesByStudent: [String: [CDNote]]
}

struct GroupRecapPairKey: Hashable {
    let lessonID: String
    let studentID: String
}

// MARK: - Note Snapshot Bridge

extension GroupRecapNote {
    init(from note: CDNote) {
        self.init(
            id: note.id ?? UUID(),
            body: note.body,
            createdAt: note.createdAt,
            category: note.categoryRaw,
            isPinned: note.isPinned
        )
    }
}
