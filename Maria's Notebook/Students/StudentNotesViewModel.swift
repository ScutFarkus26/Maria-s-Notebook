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
    }

    public let id: UUID
    public let date: Date
    public let body: String
    public let source: Source
    public let contextText: String
    public let color: Color
    public let associatedID: UUID?
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
                associatedID: note.id // link back to the Note as the source object
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
                    associatedID: assoc
                )
            }
            aggregated.append(contentsOf: workItems)
        }

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
        case .work:
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
        let byID: [UUID: Lesson] = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })

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
