// StudentNotesViewModel.swift
// Aggregates all notes for a specific Student

import SwiftUI
import SwiftData

// MARK: - Unified Item
public struct UnifiedNoteItem: Identifiable {
    public enum Source {
        case general
        case lesson
        case work
        case meeting
        case presentation
        case attendance // Added for clarity, though mapped to .general in UI if needed
    }

    public let id: UUID
    public let date: Date
    public let body: String
    public let source: Source
    public let contextText: String
    public let color: Color
    public let associatedID: UUID?
    public let category: NoteCategory
    public let includeInReport: Bool
    public let imagePath: String?
    public let reportedBy: String?
    public let reporterName: String?
    public let isPinned: Bool
}

// MARK: - View Model
@Observable
@MainActor
final class StudentNotesViewModel {
    private let student: Student
    let modelContext: ModelContext
    private let saveCoordinator: SaveCoordinator

    var items: [UnifiedNoteItem] = []

    // Pagination support
    private let pageSize: Int = 30
    private(set) var displayedItemCount: Int = 0
    private(set) var hasMoreItems: Bool = true

    var displayedItems: [UnifiedNoteItem] {
        Array(items.prefix(displayedItemCount))
    }

    init(student: Student, modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        self.student = student
        self.modelContext = modelContext
        self.saveCoordinator = saveCoordinator
        fetchAllNotes()
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, functionName: String = #function) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("⚠️ [\(functionName)] Failed to fetch \(T.self): \(error)")
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
        var aggregated: [UnifiedNoteItem] = []
        let studentIDString = student.id.uuidString

        // 1) General (Note) objects where scope matches .student(student.id)
        let noteSort: [SortDescriptor<Note>] = [
            SortDescriptor(\Note.updatedAt, order: .reverse),
            SortDescriptor(\Note.createdAt, order: .reverse)
        ]
        
        // Fetch notes that match at database level: scopeIsAll OR searchIndexStudentID matches
        let studentID = student.id
        let primaryFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.scopeIsAll == true || note.searchIndexStudentID == studentID
            },
            sortBy: noteSort
        )
        let primaryNotes: [Note] = safeFetch(primaryFetch)

        // Fetch notes with multi-student scope using NoteStudentLink for efficiency
        // This replaces the previous in-memory filtering approach
        // Note: studentIDString already declared above
        let linkFetch = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { link in
                link.studentID == studentIDString
            }
        )
        let links: [NoteStudentLink] = safeFetch(linkFetch)
        let linkedNotes = links.compactMap { $0.note }

        // Combine results, deduplicating by note ID
        var seenIDs = Set(primaryNotes.map { $0.id })
        var visibleNotes = primaryNotes
        for note in linkedNotes {
            if !seenIDs.contains(note.id) {
                seenIDs.insert(note.id)
                visibleNotes.append(note)
            }
        }
        
        // FILTERING: Exclude notes attached to specific contexts that have their own fetch blocks.
        // This prevents "leaking" notes from other students if they were created with 'All' scope.
        let generalItems: [UnifiedNoteItem] = visibleNotes.compactMap { note in
            // Exclude if attached to Work (handled by Block 2)
            if note.work != nil { return nil }
            // Exclude if attached to Presentation (handled by Block 3)
            if note.lessonAssignment != nil { return nil }
            // Exclude if attached to StudentMeeting (handled by Block 4)
            if note.studentMeeting != nil { return nil }
            // FIX: Exclude if attached to AttendanceRecord (handled by Block 5)
            if note.attendanceRecord != nil { return nil }
            
            let context: String = {
                if let lesson = note.lesson {
                    let name = lesson.name.trimmed()
                    return name.isEmpty ? "Lesson" : name
                }
                return "General Note"
            }()
            
            return UnifiedNoteItem(
                id: note.id,
                date: note.updatedAt,
                body: note.body,
                source: .general,
                contextText: context,
                color: .blue, // Blue for general
                associatedID: note.id,
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath,
                reportedBy: note.reportedBy,
                reporterName: note.reporterName,
                isPinned: note.isPinned
            )
        }
        aggregated.append(contentsOf: generalItems)

        // 2) Work-related notes (using WorkModel)
        let workFetch = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.studentID == studentIDString }
        )
        let workModels: [WorkModel] = safeFetch(workFetch)
        let workIDs = Set(workModels.map { $0.id })

        if !workIDs.isEmpty {
            // Fetch notes with work relationship (preferred)
            let workNoteFetch = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { $0.work != nil },
                sortBy: noteSort
            )
            let workNotes: [Note] = safeFetch(workNoteFetch)
            let lessonNameByWorkID: [String: String] = buildLessonNameLookup(forWorkModels: workModels)

            let workItems: [UnifiedNoteItem] = workNotes.compactMap { note in
                guard let work = note.work, workIDs.contains(work.id) else { return nil }
                
                if !note.scopeIsAll && note.searchIndexStudentID == nil {
                     guard note.scope.applies(to: student.id) else { return nil }
                }
                
                let context = lessonNameByWorkID[work.id.uuidString] ?? (work.title.isEmpty ? "Work" : work.title)
                return UnifiedNoteItem(
                    id: note.id,
                    date: note.updatedAt,
                    body: note.body,
                    source: .work,
                    contextText: context,
                    color: .orange,
                    associatedID: work.id,
                    category: note.category,
                    includeInReport: note.includeInReport,
                    imagePath: note.imagePath,
                    reportedBy: note.reportedBy,
                    reporterName: note.reporterName,
                    isPinned: note.isPinned
                )
            }
            aggregated.append(contentsOf: workItems)
        }
        
        // 3) Presentation-related notes (from LessonAssignment - the unified model)
        let presentationNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.lessonAssignment != nil },
            sortBy: noteSort
        )
        let presentationNotes: [Note] = safeFetch(presentationNoteFetch)
        let allLessons: [Lesson] = safeFetch(FetchDescriptor<Lesson>())
        var lessonsByID: [UUID: Lesson] = [:]
        for lesson in allLessons { lessonsByID[lesson.id] = lesson }

        let presentationItems: [UnifiedNoteItem] = presentationNotes.compactMap { note in
            guard let pres = note.lessonAssignment,
                  pres.studentIDs.contains(studentIDString) else { return nil }

            guard note.scope.applies(to: student.id) else { return nil }

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
                id: note.id,
                date: note.updatedAt,
                body: note.body,
                source: .presentation,
                contextText: context,
                color: .purple,
                associatedID: pres.id,
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath,
                reportedBy: note.reportedBy,
                reporterName: note.reporterName,
                isPinned: note.isPinned
            )
        }
        aggregated.append(contentsOf: presentationItems)

        // 4) Meeting-related notes
        let meetingFetch = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate<StudentMeeting> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\StudentMeeting.date, order: .reverse)]
        )
        let studentMeetings: [StudentMeeting] = safeFetch(meetingFetch)
        
        let meetingItems: [UnifiedNoteItem] = studentMeetings.flatMap { meeting -> [UnifiedNoteItem] in
            var items: [UnifiedNoteItem] = []
            if !meeting.reflection.isEmpty { items.append(makeMeetingNote(meeting, body: meeting.reflection, context: "Meeting - Reflection")) }
            if !meeting.focus.isEmpty { items.append(makeMeetingNote(meeting, body: meeting.focus, context: "Meeting - Focus")) }
            if !meeting.requests.isEmpty { items.append(makeMeetingNote(meeting, body: meeting.requests, context: "Meeting - Requests")) }
            if !meeting.guideNotes.isEmpty { items.append(makeMeetingNote(meeting, body: meeting.guideNotes, context: "Meeting - Guide Notes")) }
            return items
        }
        aggregated.append(contentsOf: meetingItems)

        // 5) Attendance-related notes (NEW BLOCK)
        // Fetch full Note objects attached to attendance records
        // First get all notes with an attendance record, then filter for our student's records
        let attNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.attendanceRecord != nil },
            sortBy: noteSort
        )
        let attNotes: [Note] = safeFetch(attNoteFetch)
        
        let linkedAttItems: [UnifiedNoteItem] = attNotes.compactMap { note in
            guard let record = note.attendanceRecord,
                  record.studentID == studentIDString else { return nil }
            
            // Safety check on scope
            guard note.scope.applies(to: student.id) else { return nil }

            return UnifiedNoteItem(
                id: note.id,
                date: note.updatedAt,
                body: note.body,
                source: .attendance,
                contextText: "Attendance Note",
                color: record.status.color,
                associatedID: record.id,
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath,
                reportedBy: note.reportedBy,
                reporterName: note.reporterName,
                isPinned: note.isPinned
            )
        }
        aggregated.append(contentsOf: linkedAttItems)

        // Deduplicate and Sort
        var uniqueMap: [UUID: UnifiedNoteItem] = [:]
        for item in aggregated {
            uniqueMap[item.id] = item
        }
        self.items = Array(uniqueMap.values).sorted { $0.date > $1.date }

        // Reset pagination
        loadInitialPage()
    }
    
    private func makeMeetingNote(_ meeting: StudentMeeting, body: String, context: String) -> UnifiedNoteItem {
        UnifiedNoteItem(
            id: UUID(),
            date: meeting.date,
            body: body,
            source: .meeting,
            contextText: context,
            color: .green,
            associatedID: meeting.id,
            category: .general,
            includeInReport: false,
            imagePath: nil,
            reportedBy: nil,
            reporterName: nil,
            isPinned: false
        )
    }

    // MARK: - Add
    func addGeneralNote(body: String) {
        let trimmed = body.trimmed()
        guard !trimmed.isEmpty else { return }

        let newNote = Note(
            body: trimmed,
            scope: .student(student.id)
        )
        modelContext.insert(newNote)

        if saveCoordinator.save(modelContext, reason: "Adding note") {
            fetchAllNotes()
        }
    }

    // MARK: - Delete
    func delete(item: UnifiedNoteItem) {
        if let note = fetchNote(id: item.id) {
            // Clean up associated image file before deleting the note
            note.deleteAssociatedImage()
            modelContext.delete(note)
            if saveCoordinator.save(modelContext, reason: "Deleting note") {
                items.removeAll { $0.id == item.id }
            }
        }
    }

    // MARK: - Helpers
    private func fetchNote(id: UUID) -> Note? {
        let d = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == id }
        )
        return modelContext.safeFetchFirst(d)
    }
    
    // Public method to fetch a note by ID (used by views)
    func note(by id: UUID) -> Note? {
        return fetchNote(id: id)
    }

    private func buildLessonNameLookup(forWorkModels workModels: [WorkModel]) -> [String: String] {
        let lessonIDs = Set(workModels.compactMap { UUID(uuidString: $0.lessonID) })
        guard !lessonIDs.isEmpty else { return [:] }

        let allLessons: [Lesson] = safeFetch(FetchDescriptor<Lesson>())
        let lessons = allLessons.filter { lessonIDs.contains($0.id) }
        var byID: [UUID: Lesson] = [:]
        for lesson in lessons {
            byID[lesson.id] = lesson
        }

        var map: [String: String] = [:]
        for work in workModels {
            if let lid = UUID(uuidString: work.lessonID), let lesson = byID[lid] {
                let name = lesson.name.trimmed()
                map[work.id.uuidString] = name.isEmpty ? "Work" : name
            } else {
                map[work.id.uuidString] = work.title.isEmpty ? "Work" : work.title
            }
        }
        return map
    }

    // MARK: - Batch Operations

    func batchDelete(ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.deleteAssociatedImage()
                modelContext.delete(note)
            }
        }
        if saveCoordinator.save(modelContext, reason: "Batch deleting notes") {
            items.removeAll { ids.contains($0.id) }
        }
    }

    func batchUpdateCategory(_ category: NoteCategory, for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.category = category
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(modelContext, reason: "Updating note categories") {
            fetchAllNotes()
        }
    }

    func batchToggleReportFlag(for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.includeInReport.toggle()
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(modelContext, reason: "Toggling report flags") {
            fetchAllNotes()
        }
    }

    func batchTogglePin(for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.isPinned.toggle()
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(modelContext, reason: "Toggling pin status") {
            fetchAllNotes()
        }
    }
}
