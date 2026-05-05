// GroupRecapResolver.swift
// Builds a `GroupRecap` snapshot from the live Core Data store. Orchestrates
// the bulk fetches in GroupRecapDataLoader and the note distribution in
// GroupRecapNoteBucketer, then walks each (student × lesson) pair to assemble
// per-student entries.
//
// Notes on cross-store FKs:
//   * CDNote.lessonID is a string FK to CDLesson (cross-store, private→shared).
//   * CDNote.lessonAssignment / .work / .workCheckIn are intra-store
//     private→private relationships used to find each note's most-specific bucket.

import Foundation
import CoreData

enum GroupRecapResolver {

    // MARK: - Public Entry Point

    /// Builds a `GroupRecap` for the given lesson + students. Returns nil when there's
    /// nothing meaningful to show (lesson has no group, or no lessons in the group).
    @MainActor
    static func resolve(
        currentLesson: CDLesson?,
        students: [CDStudent],
        context: NSManagedObjectContext
    ) -> GroupRecap? {
        guard let currentLesson else { return nil }
        let groupName = currentLesson.group
        let subject = currentLesson.subject
        guard !groupName.isEmpty else { return nil }

        let lessons = GroupRecapDataLoader.fetchLessonsInGroup(
            group: groupName,
            subject: subject,
            context: context
        )
        guard !lessons.isEmpty else { return nil }

        let lessonsInGroup = lessons.compactMap {
            lessonSummary(from: $0, currentLessonID: currentLesson.id)
        }
        let lessonIDStrings = lessons.compactMap { $0.id?.uuidString }
        let studentIDStrings = students.compactMap { $0.id?.uuidString }

        guard !studentIDStrings.isEmpty else {
            return GroupRecap(
                groupName: groupName,
                subject: subject,
                lessonsInGroup: lessonsInGroup,
                studentEntries: []
            )
        }

        let collected = GroupRecapDataLoader.collect(
            lessonIDs: lessonIDStrings,
            studentIDs: studentIDStrings,
            context: context
        )
        let buckets = GroupRecapNoteBucketer.bucket(
            notes: collected.notes,
            studentLinks: collected.studentLinks,
            studentIDSet: Set(studentIDStrings),
            lessonIDSet: Set(lessonIDStrings)
        )

        let studentEntries: [GroupRecapStudentEntry] = students.compactMap { student in
            guard let sid = student.id else { return nil }
            return buildStudentEntry(
                student: student,
                studentID: sid,
                lessonsInGroup: lessonsInGroup,
                collected: collected,
                buckets: buckets
            )
        }

        return GroupRecap(
            groupName: groupName,
            subject: subject,
            lessonsInGroup: lessonsInGroup,
            studentEntries: studentEntries
        )
    }

    // MARK: - Lesson Summary

    private static func lessonSummary(
        from lesson: CDLesson,
        currentLessonID: UUID?
    ) -> GroupRecapLesson? {
        guard let id = lesson.id else { return nil }
        return GroupRecapLesson(
            id: id,
            name: lesson.name,
            orderInGroup: Int(lesson.orderInGroup),
            isCurrent: id == currentLessonID
        )
    }

    // MARK: - Per-Student Entry

    @MainActor
    private static func buildStudentEntry(
        student: CDStudent,
        studentID: UUID,
        lessonsInGroup: [GroupRecapLesson],
        collected: GroupRecapCollectedData,
        buckets: GroupRecapNoteBuckets
    ) -> GroupRecapStudentEntry {
        let studentIDString = studentID.uuidString
        let lessonEntries = lessonsInGroup.map { lessonRecap in
            buildLessonEntry(
                studentIDString: studentIDString,
                lessonInGroup: lessonRecap,
                collected: collected,
                buckets: buckets
            )
        }
        let orphan = (buckets.orphanNotesByStudent[studentIDString] ?? [])
            .map { GroupRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return GroupRecapStudentEntry(
            id: studentID,
            studentName: student.fullName,
            lessonEntries: lessonEntries,
            orphanNotes: orphan
        )
    }

    @MainActor
    private static func buildLessonEntry(
        studentIDString: String,
        lessonInGroup: GroupRecapLesson,
        collected: GroupRecapCollectedData,
        buckets: GroupRecapNoteBuckets
    ) -> GroupRecapLessonEntry {
        let lessonIDString = lessonInGroup.id.uuidString
        let pairKey = GroupRecapPairKey(lessonID: lessonIDString, studentID: studentIDString)

        let presentations = buildPresentations(
            studentIDString: studentIDString,
            lessonIDString: lessonIDString,
            collected: collected,
            buckets: buckets
        )
        let workItems = buildWorkItems(pairKey: pairKey, collected: collected, buckets: buckets)
        let directNotes = (buckets.directNotesByPair[pairKey] ?? [])
            .map { GroupRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let lp = collected.presentationByPair[pairKey]

        return GroupRecapLessonEntry(
            id: lessonInGroup.id,
            lessonName: lessonInGroup.name,
            isCurrentLesson: lessonInGroup.isCurrent,
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
        collected: GroupRecapCollectedData,
        buckets: GroupRecapNoteBuckets
    ) -> [GroupRecapPresentation] {
        let assignmentsForLesson = collected.assignmentsByLesson[lessonIDString] ?? []
        let participating = assignmentsForLesson
            .filter { $0.studentIDs.contains(studentIDString) }
            .sorted { sortKey(for: $0) > sortKey(for: $1) }

        return participating.compactMap { a in
            guard let aid = a.id else { return nil }
            let attached = (buckets.notesByAssignment[aid.uuidString] ?? [])
                .map { GroupRecapNote(from: $0) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return GroupRecapPresentation(
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
        pairKey: GroupRecapPairKey,
        collected: GroupRecapCollectedData,
        buckets: GroupRecapNoteBuckets
    ) -> [GroupRecapWorkItem] {
        let workForPair = (collected.workByPair[pairKey] ?? [])
            .sorted { sortKey(for: $0) > sortKey(for: $1) }
        return workForPair.compactMap { work in
            buildWorkItem(work: work, buckets: buckets)
        }
    }

    @MainActor
    private static func buildWorkItem(
        work: CDWorkModel,
        buckets: GroupRecapNoteBuckets
    ) -> GroupRecapWorkItem? {
        guard let wid = work.id else { return nil }
        let checkIns = ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        let checkInSnapshots: [GroupRecapCheckIn] = checkIns.compactMap { ci in
            guard let ciid = ci.id else { return nil }
            let ciNotes = (buckets.notesByCheckIn[ciid.uuidString] ?? [])
                .map { GroupRecapNote(from: $0) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return GroupRecapCheckIn(
                id: ciid,
                date: ci.date,
                status: ci.status,
                purpose: ci.purpose,
                notes: ciNotes
            )
        }

        let workNotes = (buckets.notesByWork[wid.uuidString] ?? [])
            .map { GroupRecapNote(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return GroupRecapWorkItem(
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
