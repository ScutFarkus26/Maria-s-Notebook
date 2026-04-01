// StudentNotesViewModel.swift
// Aggregates all notes for a specific CDStudent

import OSLog
import SwiftUI
import CoreData

// MARK: - View Model
@Observable
@MainActor
final class StudentNotesViewModel {
    private static let logger = Logger.students

    private let student: CDStudent
    let viewContext: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator

    var items: [UnifiedNoteItem] = []

    // Pagination support
    private let pageSize: Int = 30
    private(set) var displayedItemCount: Int = 0
    private(set) var hasMoreItems: Bool = true

    var displayedItems: [UnifiedNoteItem] {
        Array(items.prefix(displayedItemCount))
    }

    init(student: CDStudent, viewContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        self.student = student
        self.viewContext = viewContext
        self.saveCoordinator = saveCoordinator
        fetchAllNotes()
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(_ descriptor: NSFetchRequest<T>, functionName: String = #function) -> [T] {
        do {
            return try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning(
                "Failed to fetch \(T.self, privacy: .public) in \(functionName, privacy: .public): \(error)"
            )
            return []
        }
    }

    func loadInitialPage() {
        displayedItemCount = min(pageSize, items.count)
        hasMoreItems = displayedItemCount < items.count
    }

    func loadMoreIfNeeded() {
        guard hasMoreItems else { return }
        let newCount = min(displayedItemCount + pageSize, items.count)
        displayedItemCount = newCount
        hasMoreItems = newCount < items.count
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

        loadInitialPage()
    }

    // MARK: - Add
    func addGeneralNote(body: String) {
        let trimmed = body.trimmed()
        guard !trimmed.isEmpty else { return }

        let newNote = CDNote(context: viewContext)
        newNote.body = trimmed
        if let studentID = student.id {
            newNote.scope = .student(studentID)
        }

        if saveCoordinator.save(viewContext, reason: "Adding note") {
            fetchAllNotes()
        }
    }

    // MARK: - Delete
    func delete(item: UnifiedNoteItem) {
        if let note = note(by: item.id) {
            note.deleteAssociatedImage()
            viewContext.delete(note)
            if saveCoordinator.save(viewContext, reason: "Deleting note") {
                items.removeAll { $0.id == item.id }
            }
        }
    }

}

// MARK: - CDNote Source Fetchers

extension StudentNotesViewModel {

    /// 1) General notes where scope matches this student.
    func fetchGeneralNotes(
        noteSort: [NSSortDescriptor], studentIDString: String
    ) -> [UnifiedNoteItem] {
        let primaryFetch: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        if let studentID = student.id {
            primaryFetch.predicate = NSPredicate(format: "scopeIsAll == YES OR searchIndexStudentID == %@", studentID as CVarArg)
        } else {
            primaryFetch.predicate = NSPredicate(format: "scopeIsAll == YES")
        }
        primaryFetch.sortDescriptors = noteSort
        let primaryNotes: [CDNote] = safeFetch(primaryFetch)

        let linkFetch: NSFetchRequest<CDNoteStudentLink> = NSFetchRequest(entityName: "NoteStudentLink")
        linkFetch.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        let links: [CDNoteStudentLink] = safeFetch(linkFetch)
        let linkedNotes = links.compactMap(\.note)

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
            if note.attendanceRecord != nil { return nil }

            let context: String = {
                if let lesson = note.lesson {
                    let name = lesson.name.trimmed()
                    return name.isEmpty ? "Lesson" : name
                }
                return "General CDNote"
            }()

            return UnifiedNoteItem(
                id: noteID, date: note.updatedAt ?? Date(), body: note.body,
                source: .general, contextText: context, color: .blue,
                associatedID: noteID, tags: note.tagsArray,
                includeInReport: note.includeInReport, needsFollowUp: note.needsFollowUp,
                imagePath: note.imagePath, reportedBy: note.reportedBy,
                reporterName: note.reporterName, isPinned: note.isPinned
            )
        }
    }

    /// 2) Work-related notes.
    func fetchWorkRelatedNotes(
        noteSort: [NSSortDescriptor], studentIDString: String
    ) -> [UnifiedNoteItem] {
        let workFetch: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        workFetch.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        let workModels: [CDWorkModel] = safeFetch(workFetch)
        let workIDs = Set(workModels.compactMap(\.id))
        guard !workIDs.isEmpty else { return [] }

        let workNoteFetch: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        workNoteFetch.predicate = NSPredicate(format: "work != nil")
        workNoteFetch.sortDescriptors = noteSort
        let workNotes: [CDNote] = safeFetch(workNoteFetch)
        let lessonNameByWorkID = buildLessonNameLookup(forWorkModels: workModels)

        return workNotes.compactMap { note in
            guard let noteID = note.id,
                  let work = note.work,
                  let workID = work.id,
                  workIDs.contains(workID) else { return nil }
            if !note.scopeIsAll && note.searchIndexStudentID == nil {
                guard let studentID = student.id, note.scope.applies(to: studentID) else { return nil }
            }
            let context = lessonNameByWorkID[workID.uuidString] ?? (work.title.isEmpty ? "Work" : work.title)
            return UnifiedNoteItem(
                id: noteID, date: note.updatedAt ?? Date(), body: note.body,
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
        let presentationNoteFetch: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        presentationNoteFetch.predicate = NSPredicate(format: "lessonAssignment != nil")
        presentationNoteFetch.sortDescriptors = noteSort
        let presentationNotes: [CDNote] = safeFetch(presentationNoteFetch)
        let allLessons: [CDLesson] = safeFetch(NSFetchRequest<CDLesson>(entityName: "Lesson"))
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
                id: noteID, date: note.updatedAt ?? Date(), body: note.body,
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
        let meetingFetch: NSFetchRequest<CDStudentMeeting> = NSFetchRequest(entityName: "StudentMeeting")
        meetingFetch.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        meetingFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)]
        let studentMeetings: [CDStudentMeeting] = safeFetch(meetingFetch)

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

    /// 5) Attendance-related notes.
    func fetchAttendanceNotes(
        noteSort: [NSSortDescriptor], studentIDString: String) -> [UnifiedNoteItem] {
        let attNoteFetch: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        attNoteFetch.predicate = NSPredicate(format: "attendanceRecord != nil")
        attNoteFetch.sortDescriptors = noteSort
        let attNotes: [CDNote] = safeFetch(attNoteFetch)

        return attNotes.compactMap { note in
            guard let noteID = note.id,
                  let record = note.attendanceRecord,
                  record.studentID == studentIDString else { return nil }
            guard let studentID = student.id, note.scope.applies(to: studentID) else { return nil }

            return UnifiedNoteItem(
                id: noteID, date: note.updatedAt ?? Date(), body: note.body,
                source: .attendance, contextText: "Attendance CDNote",
                color: record.status.color, associatedID: record.id,
                tags: note.tagsArray, includeInReport: note.includeInReport,
                needsFollowUp: note.needsFollowUp, imagePath: note.imagePath,
                reportedBy: note.reportedBy, reporterName: note.reporterName,
                isPinned: note.isPinned
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

        let allLessons: [CDLesson] = safeFetch(NSFetchRequest<CDLesson>(entityName: "Lesson"))
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
