// StudentNotesViewModel.swift
// Aggregates all notes for a specific CDStudent

import CoreData
import SwiftUI

// MARK: - View Model
@Observable
final class StudentNotesViewModel {
    let student: CDStudent
    let viewContext: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator

    var items: [UnifiedNoteItem] = []

    init(student: CDStudent, viewContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        self.student = student
        self.viewContext = viewContext
        self.saveCoordinator = saveCoordinator
        fetchAllNotes()
    }

    // MARK: - Fetch
    func fetchAllNotes() {
        let studentIDString = student.id?.uuidString ?? ""
        let noteSort: [NSSortDescriptor] = [
            NSSortDescriptor(keyPath: \CDNote.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)
        ]

        var aggregated: [UnifiedNoteItem] = []
        aggregated.append(contentsOf: fetchGeneralNotes(noteSort: noteSort, studentIDString: studentIDString))
        aggregated.append(contentsOf: fetchWorkRelatedNotes(noteSort: noteSort, studentIDString: studentIDString))
        aggregated.append(contentsOf: fetchPresentationNotes(noteSort: noteSort, studentIDString: studentIDString))
        aggregated.append(contentsOf: fetchMeetingNotes(studentIDString: studentIDString))
        aggregated.append(contentsOf: fetchAttendanceNotes(noteSort: noteSort, studentIDString: studentIDString))

        // Deduplicate and Sort
        var uniqueMap: [UUID: UnifiedNoteItem] = [:]
        for item in aggregated { uniqueMap[item.id] = item }
        self.items = Array(uniqueMap.values).sorted { $0.date > $1.date }
    }

    // MARK: - Add

    /// Adds a note from the tab's quick bar. Returns whether it saved, so the
    /// bar keeps her text when it didn't (it used to clear it either way). A
    /// note that couldn't be saved is taken back out, so trying again makes
    /// one note, not two.
    @discardableResult
    func addGeneralNote(body: String) -> Bool {
        let trimmed = body.trimmed()
        guard !trimmed.isEmpty else { return false }

        let newNote = CDNote(context: viewContext)
        newNote.body = trimmed
        if let studentID = student.id {
            newNote.scope = .student(studentID)
        }

        guard saveCoordinator.save(viewContext, reason: "Adding note") else {
            viewContext.delete(newNote)
            return false
        }
        NotificationCenter.default.post(name: .noteDidSave, object: newNote.id)
        fetchAllNotes()
        return true
    }

    // MARK: - Delete

    /// Deletes the note, then its photo once the delete has saved: deleted
    /// first, a failed save left the note pointing at a photo that was gone.
    func delete(item: UnifiedNoteItem) {
        guard let note = note(by: item.id) else { return }
        let imagePath = note.imagePath
        viewContext.delete(note)
        if saveCoordinator.save(viewContext, reason: "Deleting note") {
            Self.deletePhotos([imagePath])
            items.removeAll { $0.id == item.id }
        }
    }
}

// MARK: - CDNote Source Fetchers

extension StudentNotesViewModel {
    /// 1) General notes where scope matches this student.
    func fetchGeneralNotes(
        noteSort: [NSSortDescriptor], studentIDString: String
    ) -> [UnifiedNoteItem] {
        let primaryFetch = CDFetchRequest(CDNote.self)
        if let studentID = student.id {
            primaryFetch.predicate = NSPredicate(
                format: "scopeIsAll == YES OR searchIndexStudentID == %@",
                studentID as CVarArg
            )
        } else {
            primaryFetch.predicate = NSPredicate(format: "scopeIsAll == YES")
        }
        primaryFetch.sortDescriptors = noteSort
        let primaryNotes: [CDNote] = viewContext.safeFetch(primaryFetch)

        let linkFetch: NSFetchRequest<CDNoteStudentLink> = NSFetchRequest(entityName: "NoteStudentLink")
        linkFetch.predicate = NSPredicate(format: "studentID ==[c] %@", studentIDString as CVarArg)
        let links: [CDNoteStudentLink] = viewContext.safeFetch(linkFetch)
        // A link counts only while the note's scope still names her: a link
        // left by an older re-scope doesn't put the note on her tab.
        let linkedNotes = links.compactMap(\.note).filter { note in
            guard let studentID = student.id else { return false }
            return note.scope.applies(to: studentID)
        }

        // One row per note, however many links name her (two devices could
        // each link the same child).
        var seenIDs = Set(primaryNotes.compactMap(\.id))
        var visibleNotes = primaryNotes
        for note in linkedNotes {
            guard let noteID = note.id, !seenIDs.contains(noteID) else { continue }
            seenIDs.insert(noteID)
            visibleNotes.append(note)
        }

        return visibleNotes.compactMap { note in
            guard let noteID = note.id else { return nil }
            if note.work != nil { return nil }
            if note.lessonAssignment != nil { return nil }
            if note.studentMeeting != nil { return nil }
            if note.attendanceRecordID != nil { return nil }
            if !isOnProject(note) { return nil }

            return UnifiedNoteItem(
                id: noteID, date: Self.noteDate(note), body: note.body,
                source: .general, contextText: Self.generalContext(for: note), color: .blue,
                associatedID: noteID, tags: note.tagsArray,
                includeInReport: note.includeInReport, needsFollowUp: note.needsFollowUp,
                imagePath: note.imagePath, reportedBy: note.reportedBy,
                reporterName: note.reporterName, isPinned: note.isPinned
            )
        }
    }

    /// 2) Work-related notes: on her own work rows and on shared rows she's a
    /// participant in (those used to show only on the owner's tab).
    func fetchWorkRelatedNotes(
        noteSort: [NSSortDescriptor], studentIDString: String
    ) -> [UnifiedNoteItem] {
        let workFetch = CDFetchRequest(CDWorkModel.self)
        workFetch.predicate = NSPredicate(
            format: "studentID ==[c] %@ OR ANY participants.studentID ==[c] %@",
            studentIDString as CVarArg, studentIDString as CVarArg
        )
        let workModels: [CDWorkModel] = viewContext.safeFetch(workFetch)
        let workIDs = Set(workModels.compactMap(\.id))
        guard !workIDs.isEmpty else { return [] }

        let workNoteFetch = CDFetchRequest(CDNote.self)
        workNoteFetch.predicate = NSPredicate(format: "work IN %@", workModels)
        workNoteFetch.sortDescriptors = noteSort
        let workNotes: [CDNote] = viewContext.safeFetch(workNoteFetch)
        let lessonNameByWorkID = buildLessonNameLookup(forWorkModels: workModels)

        return workNotes.compactMap { note in
            guard let noteID = note.id,
                  let work = note.work,
                  let workID = work.id,
                  workIDs.contains(workID),
                  let studentID = student.id else { return nil }
            // The owner sees a note unless it names other children only; a
            // participant sees the row's whole-class notes and those naming her.
            let isOwner = work.studentID.caseInsensitiveCompare(studentIDString) == .orderedSame
            let isHers = note.scopeIsAll || note.scope.applies(to: studentID)
            guard isHers || (isOwner && note.searchIndexStudentID != nil) else { return nil }
            let context = lessonNameByWorkID[workID.uuidString] ?? (work.title.isEmpty ? "Work" : work.title)
            return UnifiedNoteItem(
                id: noteID, date: Self.noteDate(note), body: note.body,
                source: .work, contextText: context, color: .orange,
                associatedID: workID, tags: note.tagsArray,
                includeInReport: note.includeInReport, needsFollowUp: note.needsFollowUp,
                imagePath: note.imagePath, reportedBy: note.reportedBy,
                reporterName: note.reporterName, isPinned: note.isPinned
            )
        }
    }

    /// 3) Presentation-related notes (from CDLessonAssignment).
    func fetchPresentationNotes(
        noteSort: [NSSortDescriptor], studentIDString: String
    ) -> [UnifiedNoteItem] {
        let presentationNoteFetch = CDFetchRequest(CDNote.self)
        presentationNoteFetch.predicate = NSPredicate(format: "lessonAssignment != nil")
        presentationNoteFetch.sortDescriptors = noteSort
        let presentationNotes: [CDNote] = viewContext.safeFetch(presentationNoteFetch)
        let allLessons: [CDLesson] = viewContext.safeFetch(CDFetchRequest(CDLesson.self))
        var lessonsByID: [UUID: CDLesson] = [:]
        for lesson in allLessons {
            if let lessonID = lesson.id { lessonsByID[lessonID] = lesson }
        }

        return presentationNotes.compactMap { note in
            guard let noteID = note.id,
                  let pres = note.lessonAssignment,
                  pres.studentIDs.contains(studentIDString) else { return nil }
            guard let studentID = student.id, note.scope.applies(to: studentID) else { return nil }

            let context: String = {
                if let lessonID = UUID(uuidString: pres.lessonID),
                   let lesson = lessonsByID[lessonID] {
                    let name = lesson.name.trimmed()
                    return name.isEmpty ? "Presentation" : name
                } else if let snapshot = pres.lessonTitleSnapshot?.trimmed(),
                          !snapshot.isEmpty {
                    return snapshot
                }
                return "Presentation"
            }()

            return UnifiedNoteItem(
                id: noteID, date: Self.noteDate(note), body: note.body,
                source: .presentation, contextText: context, color: .purple,
                associatedID: pres.id, tags: note.tagsArray,
                includeInReport: note.includeInReport, needsFollowUp: note.needsFollowUp,
                imagePath: note.imagePath, reportedBy: note.reportedBy,
                reporterName: note.reporterName, isPinned: note.isPinned
            )
        }
    }

    /// 4) Meeting-related notes.
    func fetchMeetingNotes(studentIDString: String) -> [UnifiedNoteItem] {
        let meetingFetch = CDFetchRequest(CDStudentMeeting.self)
        meetingFetch.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        meetingFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)]
        let studentMeetings: [CDStudentMeeting] = viewContext.safeFetch(meetingFetch)

        return studentMeetings.flatMap { meeting -> [UnifiedNoteItem] in
            var items: [UnifiedNoteItem] = []
            if !meeting.reflection.isEmpty {
                items.append(makeMeetingNote(meeting, body: meeting.reflection, context: "Meeting - Reflection"))
            }
            if !meeting.focus.isEmpty {
                items.append(makeMeetingNote(meeting, body: meeting.focus, context: "Meeting - Focus"))
            }
            if !meeting.requests.isEmpty {
                items.append(makeMeetingNote(meeting, body: meeting.requests, context: "Meeting - Requests"))
            }
            if !meeting.guideNotes.isEmpty {
                items.append(makeMeetingNote(meeting, body: meeting.guideNotes, context: "Meeting - Guide Notes"))
            }
            return items
        }
    }

    /// 5) Attendance notes: the day's note on each of this student's records.
    /// Shown read-only here — they are edited on the attendance screen, and
    /// the timeline's actions look items up as private notes.
    func fetchAttendanceNotes(
        noteSort: [NSSortDescriptor], studentIDString: String) -> [UnifiedNoteItem] {
        let recordFetch = CDFetchRequest(CDAttendanceRecord.self)
        recordFetch.predicate = NSPredicate(
            format: "studentID == %@ AND note != nil AND note != %@", studentIDString, ""
        )
        recordFetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return viewContext.safeFetch(recordFetch).compactMap { record in
            guard let id = record.id, let note = record.note else { return nil }
            return UnifiedNoteItem(
                id: id, date: record.date ?? record.modifiedAt ?? Date(), body: note,
                source: .attendance, contextText: "Attendance Note",
                color: record.status.color, associatedID: id,
                tags: [], includeInReport: false,
                needsFollowUp: false, imagePath: nil,
                reportedBy: nil, reporterName: nil,
                isPinned: false
            )
        }
    }

    func makeMeetingNote(_ meeting: CDStudentMeeting, body: String, context: String) -> UnifiedNoteItem {
        UnifiedNoteItem(
            id: UUID(),
            date: meeting.date ?? Date(),
            body: body,
            source: .meeting,
            contextText: context,
            color: .green,
            associatedID: meeting.id ?? UUID(),
            tags: [],
            includeInReport: false,
            needsFollowUp: false,
            imagePath: nil,
            reportedBy: nil,
            reporterName: nil,
            isPinned: false
        )
    }

    func buildLessonNameLookup(forWorkModels workModels: [CDWorkModel]) -> [String: String] {
        let lessonIDs = Set(workModels.compactMap { UUID(uuidString: $0.lessonID) })
        guard !lessonIDs.isEmpty else { return [:] }

        let allLessons: [CDLesson] = viewContext.safeFetch(CDFetchRequest(CDLesson.self))
        let lessons = allLessons.filter { $0.id != nil && lessonIDs.contains($0.id!) }
        var byID: [UUID: CDLesson] = [:]
        for lesson in lessons {
            if let lessonID = lesson.id { byID[lessonID] = lesson }
        }

        var map: [String: String] = [:]
        for work in workModels {
            let workIDString = work.id?.uuidString ?? UUID().uuidString
            if let lesson = byID[uuidString: work.lessonID] {
                let name = lesson.name.trimmed()
                map[workIDString] = name.isEmpty ? "Work" : name
            } else {
                map[workIDString] = work.title.isEmpty ? "Work" : work.title
            }
        }
        return map
    }
}
