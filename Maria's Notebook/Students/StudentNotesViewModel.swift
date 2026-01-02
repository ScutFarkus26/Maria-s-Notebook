// StudentNotesViewModel.swift
// Aggregates all notes for a specific Student

import SwiftUI
import SwiftData
import Combine

// MARK: - Unified Item
public struct UnifiedNoteItem: Identifiable {
    public enum Source {
        case general
        case lesson
        case work
        case meeting
        case presentation
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
}

// MARK: - View Model
@MainActor
final class StudentNotesViewModel: ObservableObject {
    private let student: Student
    private let modelContext: ModelContext

    @Published var items: [UnifiedNoteItem] = []

    init(student: Student, modelContext: ModelContext) {
        self.student = student
        self.modelContext = modelContext
        fetchAllNotes()
    }

    // MARK: - Fetch
    func fetchAllNotes() {
        var aggregated: [UnifiedNoteItem] = []

        // 1) General (Note) objects where scope matches .student(student.id)
        let noteSort: [SortDescriptor<Note>] = [
            SortDescriptor(\Note.updatedAt, order: .reverse),
            SortDescriptor(\Note.createdAt, order: .reverse)
        ]
        let noteDesc = FetchDescriptor<Note>(sortBy: noteSort)
        let allNotes: [Note] = (try? modelContext.fetch(noteDesc)) ?? []
        let visibleNotes = allNotes.filter { note in
            if case .student(let id) = note.scope { return id == student.id }
            return false
        }
        let generalItems: [UnifiedNoteItem] = visibleNotes.map { note in
            let context: String = {
                if let lesson = note.lesson {
                    let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                associatedID: note.id, // link back to the Note as the source object
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath
            )
        }
        aggregated.append(contentsOf: generalItems)

        // 2) Work-related notes from ScopedNote linked to this student's WorkContracts
        let sid = student.id.uuidString
        let workFetch = FetchDescriptor<WorkContract>(
            predicate: #Predicate<WorkContract> { $0.studentID == sid }
        )
        let contracts: [WorkContract] = (try? modelContext.fetch(workFetch)) ?? []
        let contractIDs = Set(contracts.map { $0.id.uuidString })

        if !contractIDs.isEmpty {
            let scopedSort: [SortDescriptor<ScopedNote>] = [
                SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
                SortDescriptor(\ScopedNote.createdAt, order: .reverse)
            ]
            // Fetch notes that have a workContractID, then filter in-memory for the id set
            let scopedFetch = FetchDescriptor<ScopedNote>(
                predicate: #Predicate<ScopedNote> { $0.workContractID != nil },
                sortBy: scopedSort
            )
            let scoped: [ScopedNote] = (try? modelContext.fetch(scopedFetch)) ?? []
            // Build a quick lookup for contract -> lesson name (best-effort)
            let lessonNameByContractID: [String: String] = buildLessonNameLookup(for: contracts)

            let workItems: [UnifiedNoteItem] = scoped.compactMap { note in
                guard let wid = note.workContractID, contractIDs.contains(wid) else { return nil }
                let context = lessonNameByContractID[wid] ?? "Work"
                let assoc = UUID(uuidString: wid)
                return UnifiedNoteItem(
                    id: note.id,
                    date: note.updatedAt,
                    body: note.body,
                    source: .work,
                    contextText: context,
                    color: .orange, // Orange for work
                    associatedID: assoc,
                    category: .general, // ScopedNote doesn't have category, default to .general
                    includeInReport: false, // ScopedNote doesn't have includeInReport, default to false
                    imagePath: nil // ScopedNote doesn't support images
                )
            }
            aggregated.append(contentsOf: workItems)
        }

        // 3) Presentation-related notes from ScopedNote linked to Presentations that include this student
        let studentIDString = student.id.uuidString
        let presentationScopedFetch = FetchDescriptor<ScopedNote>(
            predicate: #Predicate<ScopedNote> { $0.presentationID != nil },
            sortBy: [
                SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
                SortDescriptor(\ScopedNote.createdAt, order: .reverse)
            ]
        )
        let presentationScopedNotes: [ScopedNote] = (try? modelContext.fetch(presentationScopedFetch)) ?? []
        
        // Fetch all presentations to build a lookup
        let allPresentations: [Presentation] = (try? modelContext.fetch(FetchDescriptor<Presentation>())) ?? []
        // Build dictionary safely, handling potential duplicates by keeping the first occurrence
        var presentationsByID: [String: Presentation] = [:]
        for presentation in allPresentations {
            let key = presentation.id.uuidString
            if presentationsByID[key] == nil {
                presentationsByID[key] = presentation
            }
        }
        
        // Fetch all lessons for context lookup
        let allLessons: [Lesson] = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        // Build dictionary safely, handling potential duplicates by keeping the first occurrence
        var lessonsByID: [String: Lesson] = [:]
        for lesson in allLessons {
            let key = lesson.id.uuidString
            if lessonsByID[key] == nil {
                lessonsByID[key] = lesson
            }
        }
        
        let presentationItems: [UnifiedNoteItem] = presentationScopedNotes.compactMap { note in
            guard let presentationID = note.presentationID,
                  let presentation = presentationsByID[presentationID],
                  presentation.studentIDs.contains(studentIDString) else {
                return nil
            }
            
            // Get lesson name from presentation
            let context: String = {
                if let lessonID = UUID(uuidString: presentation.lessonID),
                   let lesson = lessonsByID[lessonID.uuidString] {
                    let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? "Presentation" : name
                } else if let snapshot = presentation.lessonTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !snapshot.isEmpty {
                    return snapshot
                }
                return "Presentation"
            }()
            
            let assoc = UUID(uuidString: presentationID)
            return UnifiedNoteItem(
                id: note.id,
                date: note.updatedAt,
                body: note.body,
                source: .presentation,
                contextText: context,
                color: .purple, // Purple for presentations
                associatedID: assoc,
                category: .general, // ScopedNote doesn't have category, default to .general
                includeInReport: false, // ScopedNote doesn't have includeInReport, default to false
                imagePath: nil // ScopedNote doesn't support images
            )
        }
        aggregated.append(contentsOf: presentationItems)

        // 4) Meeting-related notes from StudentMeeting records for this student
        let meetingFetch = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate<StudentMeeting> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\StudentMeeting.date, order: .reverse)]
        )
        let studentMeetings: [StudentMeeting] = (try? modelContext.fetch(meetingFetch)) ?? []
        
        // Check if StudentMeeting has a notes field or relationship to MeetingNote
        // Based on AppSchema, MeetingNote is related to CommunityTopic, not StudentMeeting
        // StudentMeeting has text fields: reflection, focus, requests, guideNotes
        // We'll create note items from these text fields if they contain content
        let meetingItems: [UnifiedNoteItem] = studentMeetings.flatMap { meeting -> [UnifiedNoteItem] in
            var items: [UnifiedNoteItem] = []
            
            // Create items from each non-empty text field
            if !meeting.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(UnifiedNoteItem(
                    id: UUID(), // Generate new ID for each field
                    date: meeting.date,
                    body: meeting.reflection,
                    source: .meeting,
                    contextText: "Meeting - Reflection",
                    color: .green, // Green for meetings
                    associatedID: meeting.id,
                    category: .general,
                    includeInReport: false,
                    imagePath: nil // StudentMeeting doesn't support images
                ))
            }
            if !meeting.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(UnifiedNoteItem(
                    id: UUID(),
                    date: meeting.date,
                    body: meeting.focus,
                    source: .meeting,
                    contextText: "Meeting - Focus",
                    color: .green,
                    associatedID: meeting.id,
                    category: .general,
                    includeInReport: false,
                    imagePath: nil // StudentMeeting doesn't support images
                ))
            }
            if !meeting.requests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(UnifiedNoteItem(
                    id: UUID(),
                    date: meeting.date,
                    body: meeting.requests,
                    source: .meeting,
                    contextText: "Meeting - Requests",
                    color: .green,
                    associatedID: meeting.id,
                    category: .general,
                    includeInReport: false,
                    imagePath: nil // StudentMeeting doesn't support images
                ))
            }
            if !meeting.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(UnifiedNoteItem(
                    id: UUID(),
                    date: meeting.date,
                    body: meeting.guideNotes,
                    source: .meeting,
                    contextText: "Meeting - Guide Notes",
                    color: .green,
                    associatedID: meeting.id,
                    category: .general,
                    includeInReport: false,
                    imagePath: nil // StudentMeeting doesn't support images
                ))
            }
            
            return items
        }
        aggregated.append(contentsOf: meetingItems)

        // Sort combined results by date (descending)
        aggregated.sort { $0.date > $1.date }
        self.items = aggregated
    }

    // MARK: - Add
    func addGeneralNote(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Create new Note with student scope
        let newNote = Note(
            body: trimmed,
            scope: .student(student.id)
        )
        modelContext.insert(newNote)

        // Save and refresh
        do {
            try modelContext.save()
            fetchAllNotes()
        } catch {
            print("Error saving new note: \(error)")
        }
    }

    // MARK: - Delete
    func delete(item: UnifiedNoteItem) {
        // Attempt to delete backing object based on known types.
        // We try Note first for .general, then fall back to ScopedNote.
        switch item.source {
        case .general, .lesson, .meeting:
            if let note = fetchNote(id: item.id) {
                modelContext.delete(note)
                try? modelContext.save()
                items.removeAll { $0.id == item.id }
                return
            }
            // If not found as Note, attempt ScopedNote
            fallthrough
        case .work, .presentation:
            if let s = fetchScopedNote(id: item.id) {
                modelContext.delete(s)
                try? modelContext.save()
                items.removeAll { $0.id == item.id }
            }
        }
    }

    // MARK: - Helpers
    private func fetchNote(id: UUID) -> Note? {
        // OPTIMIZATION: Use predicate instead of fetching all notes
        let d = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == id }
        )
        return try? modelContext.fetch(d).first
    }

    private func fetchScopedNote(id: UUID) -> ScopedNote? {
        // OPTIMIZATION: Use predicate instead of fetching all notes
        let d = FetchDescriptor<ScopedNote>(
            predicate: #Predicate<ScopedNote> { $0.id == id }
        )
        return try? modelContext.fetch(d).first
    }

    private func buildLessonNameLookup(for contracts: [WorkContract]) -> [String: String] {
        // OPTIMIZATION: Only fetch lessons that are referenced by contracts
        let lessonIDs = Set(contracts.compactMap { UUID(uuidString: $0.lessonID) })
        guard !lessonIDs.isEmpty else { return [:] }
        
        // Note: SwiftData predicates don't support Set.contains with captured values,
        // so we fetch all lessons and filter. This is still better than fetching all contracts/notes.
        let allLessons: [Lesson] = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        let lessons = allLessons.filter { lessonIDs.contains($0.id) }
        // Build dictionary safely, handling potential duplicates by keeping the first occurrence
        var byID: [UUID: Lesson] = [:]
        for lesson in lessons {
            if byID[lesson.id] == nil {
                byID[lesson.id] = lesson
            }
        }

        var map: [String: String] = [:]
        for c in contracts {
            if let lid = UUID(uuidString: c.lessonID), let lesson = byID[lid] {
                let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
                map[c.id.uuidString] = name.isEmpty ? "Work" : name
            } else {
                map[c.id.uuidString] = "Work"
            }
        }
        return map
    }
}
