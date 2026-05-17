// SequenceRecapResolver.swift
// Builds a `SequenceRecap` snapshot from the live Core Data store. Orchestrates
// the bulk fetches in SequenceRecapDataLoader and the note distribution in
// SequenceRecapNoteBucketer, then walks each (student × lesson) pair to assemble
// per-student entries.
//
// Notes on cross-store FKs:
//   * CDNote.lessonID is a string FK to CDLesson (cross-store, private→shared).
//   * CDNote.lessonAssignment / .work / .workCheckIn are intra-store
//     private→private relationships used to find each note's most-specific bucket.

import Foundation
import CoreData

enum SequenceRecapResolver {

    // MARK: - Public Entry Point

    /// Builds a `SequenceRecap` for the given lesson + students. Returns nil when there's
    /// nothing meaningful to show (lesson has no sequence, or no lessons in the sequence).
    @MainActor
    static func resolve(
        currentLesson: CDLesson?,
        students: [CDStudent],
        context: NSManagedObjectContext
    ) -> SequenceRecap? {
        guard let currentLesson else { return nil }
        let sequenceName = currentLesson.sequence
        let area = currentLesson.area
        guard !sequenceName.isEmpty else { return nil }

        let lessons = SequenceRecapDataLoader.fetchLessonsInSequence(
            sequence: sequenceName,
            area: area,
            context: context
        )
        guard !lessons.isEmpty else { return nil }

        let lessonsInSequence = lessons.compactMap {
            lessonSummary(from: $0, currentLessonID: currentLesson.id)
        }
        let lessonIDStrings = lessons.compactMap { $0.id?.uuidString }
        let studentIDStrings = students.compactMap { $0.id?.uuidString }

        guard !studentIDStrings.isEmpty else {
            return SequenceRecap(
                sequenceName: sequenceName,
                area: area,
                lessonsInSequence: lessonsInSequence,
                studentEntries: []
            )
        }

        let collected = SequenceRecapDataLoader.collect(
            lessonIDs: lessonIDStrings,
            studentIDs: studentIDStrings,
            context: context
        )
        let buckets = SequenceRecapNoteBucketer.bucket(
            notes: collected.notes,
            studentLinks: collected.studentLinks,
            studentIDSet: Set(studentIDStrings),
            lessonIDSet: Set(lessonIDStrings)
        )

        let studentEntries: [SequenceRecapStudentEntry] = students.compactMap { student in
            guard let sid = student.id else { return nil }
            return buildStudentEntry(
                student: student,
                studentID: sid,
                lessonsInSequence: lessonsInSequence,
                collected: collected,
                buckets: buckets
            )
        }

        return SequenceRecap(
            sequenceName: sequenceName,
            area: area,
            lessonsInSequence: lessonsInSequence,
            studentEntries: studentEntries
        )
    }

    // MARK: - Lesson Summary

    private static func lessonSummary(
        from lesson: CDLesson,
        currentLessonID: UUID?
    ) -> SequenceRecapLesson? {
        guard let id = lesson.id else { return nil }
        return SequenceRecapLesson(
            id: id,
            name: lesson.name,
            orderInSequence: Int(lesson.orderInSequence),
            isCurrent: id == currentLessonID
        )
    }

    // MARK: - Per-Student Entry

    @MainActor
    private static func buildStudentEntry(
        student: CDStudent,
        studentID: UUID,
        lessonsInSequence: [SequenceRecapLesson],
        collected: SequenceRecapCollectedData,
        buckets: SequenceRecapNoteBuckets
    ) -> SequenceRecapStudentEntry {
        let studentIDString = studentID.uuidString
        let lessonEntries = lessonsInSequence.map { lessonRecap in
            buildLessonEntry(
                studentIDString: studentIDString,
                lessonInSequence: lessonRecap,
                collected: collected,
                buckets: buckets
            )
        }
        let orphan = (buckets.orphanNotesByStudent[studentIDString] ?? [])
            .map { SequenceRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return SequenceRecapStudentEntry(
            id: studentID,
            studentName: student.fullName,
            lessonEntries: lessonEntries,
            orphanNotes: orphan
        )
    }

    @MainActor
    private static func buildLessonEntry(
        studentIDString: String,
        lessonInSequence: SequenceRecapLesson,
        collected: SequenceRecapCollectedData,
        buckets: SequenceRecapNoteBuckets
    ) -> SequenceRecapLessonEntry {
        let lessonIDString = lessonInSequence.id.uuidString
        let pairKey = SequenceRecapPairKey(lessonID: lessonIDString, studentID: studentIDString)

        let presentations = buildPresentations(
            studentIDString: studentIDString,
            lessonIDString: lessonIDString,
            collected: collected,
            buckets: buckets
        )
        let workItems = buildWorkItems(pairKey: pairKey, collected: collected, buckets: buckets)
        let directNotes = (buckets.directNotesByPair[pairKey] ?? [])
            .map { SequenceRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let lp = collected.presentationByPair[pairKey]

        return SequenceRecapLessonEntry(
            id: lessonInSequence.id,
            lessonName: lessonInSequence.name,
            isCurrentLesson: lessonInSequence.isCurrent,
            outcomeState: lp?.state,
            firstPresentedAt: lp?.presentedAt,
            lastObservedAt: lp?.lastObservedAt,
            masteredAt: lp?.masteredAt,
            perStudentLessonNotes: lp?.notes,
            presentations: presentations,
            workItems: workItems,
            directNotes: directNotes
        )
    }

    @MainActor
    private static func buildPresentations(
        studentIDString: String,
        lessonIDString: String,
        collected: SequenceRecapCollectedData,
        buckets: SequenceRecapNoteBuckets
    ) -> [SequenceRecapPresentation] {
        let assignmentsForLesson = collected.assignmentsByLesson[lessonIDString] ?? []
        let participating = assignmentsForLesson
            .filter { $0.studentIDs.contains(studentIDString) }
            .sorted { sortKey(for: $0) > sortKey(for: $1) }

        return participating.compactMap { a in
            guard let aid = a.id else { return nil }
            let attached = (buckets.notesByAssignment[aid.uuidString] ?? [])
                .map { SequenceRecapNote(from: $0) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return SequenceRecapPresentation(
                id: aid,
                presentedAt: a.presentedAt,
                scheduledFor: a.scheduledFor,
                state: a.state,
                needsPractice: a.needsPractice,
                needsAnotherPresentation: a.needsAnotherPresentation,
                groupNotes: a.notes,
                attachedNotes: attached
            )
        }
    }

    @MainActor
    private static func buildWorkItems(
        pairKey: SequenceRecapPairKey,
        collected: SequenceRecapCollectedData,
        buckets: SequenceRecapNoteBuckets
    ) -> [SequenceRecapWorkItem] {
        let workForPair = (collected.workByPair[pairKey] ?? [])
            .sorted { sortKey(for: $0) > sortKey(for: $1) }
        return workForPair.compactMap { work in
            buildWorkItem(work: work, buckets: buckets)
        }
    }

    @MainActor
    private static func buildWorkItem(
        work: CDWorkModel,
        buckets: SequenceRecapNoteBuckets
    ) -> SequenceRecapWorkItem? {
        guard let wid = work.id else { return nil }
        let checkIns = ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        let checkInSnapshots: [SequenceRecapCheckIn] = checkIns.compactMap { ci in
            guard let ciid = ci.id else { return nil }
            let ciNotes = (buckets.notesByCheckIn[ciid.uuidString] ?? [])
                .map { SequenceRecapNote(from: $0) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return SequenceRecapCheckIn(
                id: ciid,
                date: ci.date,
                status: ci.status,
                purpose: ci.purpose,
                notes: ciNotes
            )
        }

        let workNotes = (buckets.notesByWork[wid.uuidString] ?? [])
            .map { SequenceRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return SequenceRecapWorkItem(
            id: wid,
            title: work.title,
            kind: work.kind,
            status: work.status,
            completionOutcome: work.completionOutcome,
            assignedAt: work.assignedAt,
            completedAt: work.completedAt,
            attachedNotes: workNotes,
            checkIns: checkInSnapshots
        )
    }

    // MARK: - Sort Helpers

    private static func sortKey(for a: CDLessonAssignment) -> Date {
        a.presentedAt ?? a.scheduledFor ?? a.createdAt ?? .distantPast
    }

    private static func sortKey(for w: CDWorkModel) -> Date {
        w.completedAt ?? w.assignedAt ?? w.createdAt ?? .distantPast
    }
}
