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
        let primaryNotes: [Note] = (try? modelContext.fetch(primaryFetch)) ?? []
        
        // Also fetch notes with .students([UUID]) scope
        let multiStudentFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.scopeIsAll == false && note.searchIndexStudentID == nil
            },
            sortBy: noteSort
        )
        let multiStudentNotes: [Note] = (try? modelContext.fetch(multiStudentFetch)) ?? []
        // Filter in memory for .students([UUID]) scope
        let filteredMultiStudentNotes = multiStudentNotes.filter { $0.scope.applies(to: student.id) }
        
        // Combine results
        let visibleNotes = primaryNotes + filteredMultiStudentNotes
        
        // FILTERING: Exclude notes attached to specific contexts that have their own fetch blocks.
        // This prevents "leaking" notes from other students if they were created with 'All' scope.
        let generalItems: [UnifiedNoteItem] = visibleNotes.compactMap { note in
            // Exclude if attached to Work (handled by Block 2) - check both work and workContract
            if note.work != nil { return nil }
            if note.workContract != nil { return nil }
            // Exclude if attached to Presentation (handled by Block 3)
            if note.presentation != nil { return nil }
            // Exclude if attached to StudentMeeting (handled by Block 4)
            if note.studentMeeting != nil { return nil }
            // FIX: Exclude if attached to AttendanceRecord (handled by Block 5)
            if note.attendanceRecord != nil { return nil }
            
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
                associatedID: note.id,
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath,
                reportedBy: note.reportedBy,
                reporterName: note.reporterName
            )
        }
        aggregated.append(contentsOf: generalItems)

        // 2) Work-related notes (using WorkModel)
        let workFetch = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.studentID == studentIDString }
        )
        let workModels: [WorkModel] = (try? modelContext.fetch(workFetch)) ?? []
        let workIDs = Set(workModels.map { $0.id })

        if !workIDs.isEmpty {
            // Fetch notes with work relationship (preferred)
            let workNoteFetch = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { $0.work != nil },
                sortBy: noteSort
            )
            let workNotes: [Note] = (try? modelContext.fetch(workNoteFetch)) ?? []
            let lessonNameByWorkID: [String: String] = buildLessonNameLookup(forWorkModels: workModels)

            let workItems: [UnifiedNoteItem] = workNotes.compactMap { note in
                guard let work = note.work, workIDs.contains(work.id) else { return nil }
                
                if !note.scopeIsAll && note.searchIndexStudentID == nil {
                     guard note.scope.applies(to: student.id) else { return nil }
                }
                
                let context = lessonNameByWorkID[work.id.uuidString] ?? work.title.isEmpty ? "Work" : work.title
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
                    reporterName: note.reporterName
                )
            }
            aggregated.append(contentsOf: workItems)
        }
        
        // 2b) Legacy WorkContract notes (for backward compatibility)
        let legacyContractFetch = FetchDescriptor<WorkContract>(
            predicate: #Predicate<WorkContract> { $0.studentID == studentIDString }
        )
        let contracts: [WorkContract] = (try? modelContext.fetch(legacyContractFetch)) ?? []
        let contractIDs = Set(contracts.map { $0.id })

        if !contractIDs.isEmpty {
            let noteFetch = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { $0.workContract != nil },
                sortBy: noteSort
            )
            let fetchedNotes: [Note] = (try? modelContext.fetch(noteFetch)) ?? []
            let lessonNameByContractID: [String: String] = buildLessonNameLookup(forContracts: contracts)

            let legacyWorkItems: [UnifiedNoteItem] = fetchedNotes.compactMap { note in
                // Skip if already included via work relationship
                if note.work != nil { return nil }
                
                guard let contract = note.workContract, contractIDs.contains(contract.id) else { return nil }
                
                if !note.scopeIsAll && note.searchIndexStudentID == nil {
                     guard note.scope.applies(to: student.id) else { return nil }
                }
                
                let context = lessonNameByContractID[contract.id.uuidString] ?? "Work"
                return UnifiedNoteItem(
                    id: note.id,
                    date: note.updatedAt,
                    body: note.body,
                    source: .work,
                    contextText: context,
                    color: .orange,
                    associatedID: contract.id,
                    category: note.category,
                    includeInReport: note.includeInReport,
                    imagePath: note.imagePath,
                    reportedBy: note.reportedBy,
                    reporterName: note.reporterName
                )
            }
            aggregated.append(contentsOf: legacyWorkItems)
        }

        // 3) Presentation-related notes
        let presentationNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.presentation != nil },
            sortBy: noteSort
        )
        let presentationNotes: [Note] = (try? modelContext.fetch(presentationNoteFetch)) ?? []
        let allLessons: [Lesson] = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        var lessonsByID: [UUID: Lesson] = [:]
        for lesson in allLessons { lessonsByID[lesson.id] = lesson }
        
        let presentationItems: [UnifiedNoteItem] = presentationNotes.compactMap { note in
            guard let presentation = note.presentation,
                  presentation.studentIDs.contains(studentIDString) else { return nil }
            
            guard note.scope.applies(to: student.id) else { return nil }
            
            let context: String = {
                if let lessonID = UUID(uuidString: presentation.lessonID),
                   let lesson = lessonsByID[lessonID] {
                    let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? "Presentation" : name
                } else if let snapshot = presentation.lessonTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines),
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
                associatedID: presentation.id,
                category: note.category,
                includeInReport: note.includeInReport,
                imagePath: note.imagePath,
                reportedBy: note.reportedBy,
                reporterName: note.reporterName
            )
        }
        aggregated.append(contentsOf: presentationItems)

        // 4) Meeting-related notes
        let meetingFetch = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate<StudentMeeting> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\StudentMeeting.date, order: .reverse)]
        )
        let studentMeetings: [StudentMeeting] = (try? modelContext.fetch(meetingFetch)) ?? []
        
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
        // Fetch AttendanceRecords specifically for this student
        let attFetch = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\AttendanceRecord.date, order: .reverse)]
        )
        let attendanceRecords: [AttendanceRecord] = (try? modelContext.fetch(attFetch)) ?? []
        
        // 5a) Create items from the 'note' string field on the record itself
        let attendanceStringItems: [UnifiedNoteItem] = attendanceRecords.compactMap { record in
            guard let text = record.note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return UnifiedNoteItem(
                id: UUID(), // Virtual ID for the string note
                date: record.date,
                body: text,
                source: .attendance,
                contextText: "Attendance - \(record.status.displayName)",
                color: record.status.color, // Use the status color (e.g. Red for Absent)
                associatedID: record.id,
                category: .general,
                includeInReport: false,
                imagePath: nil,
                reportedBy: nil,
                reporterName: nil
            )
        }
        aggregated.append(contentsOf: attendanceStringItems)
        
        // 5b) Fetch full Note objects attached to these records
        // First get all notes with an attendance record, then filter for our student's records
        let attNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.attendanceRecord != nil },
            sortBy: noteSort
        )
        let attNotes: [Note] = (try? modelContext.fetch(attNoteFetch)) ?? []
        
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
                reporterName: note.reporterName
            )
        }
        aggregated.append(contentsOf: linkedAttItems)

        // Deduplicate and Sort
        var uniqueMap: [UUID: UnifiedNoteItem] = [:]
        for item in aggregated {
            uniqueMap[item.id] = item
        }
        self.items = Array(uniqueMap.values).sorted { $0.date > $1.date }
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
            reporterName: nil
        )
    }

    // MARK: - Add
    func addGeneralNote(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newNote = Note(
            body: trimmed,
            scope: .student(student.id)
        )
        modelContext.insert(newNote)

        do {
            try modelContext.save()
            fetchAllNotes()
        } catch {
            print("Error saving new note: \(error)")
        }
    }

    // MARK: - Delete
    func delete(item: UnifiedNoteItem) {
        if let note = fetchNote(id: item.id) {
            modelContext.delete(note)
            try? modelContext.save()
            items.removeAll { $0.id == item.id }
        }
    }

    // MARK: - Helpers
    private func fetchNote(id: UUID) -> Note? {
        let d = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == id }
        )
        return try? modelContext.fetch(d).first
    }
    
    // Public method to fetch a note by ID (used by views)
    func note(by id: UUID) -> Note? {
        return fetchNote(id: id)
    }

    private func buildLessonNameLookup(forWorkModels workModels: [WorkModel]) -> [String: String] {
        let lessonIDs = Set(workModels.compactMap { UUID(uuidString: $0.lessonID) })
        guard !lessonIDs.isEmpty else { return [:] }
        
        let allLessons: [Lesson] = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        let lessons = allLessons.filter { lessonIDs.contains($0.id) }
        var byID: [UUID: Lesson] = [:]
        for lesson in lessons {
            byID[lesson.id] = lesson
        }

        var map: [String: String] = [:]
        for work in workModels {
            if let lid = UUID(uuidString: work.lessonID), let lesson = byID[lid] {
                let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
                map[work.id.uuidString] = name.isEmpty ? "Work" : name
            } else {
                map[work.id.uuidString] = work.title.isEmpty ? "Work" : work.title
            }
        }
        return map
    }
    
    private func buildLessonNameLookup(forContracts contracts: [WorkContract]) -> [String: String] {
        let lessonIDs = Set(contracts.compactMap { UUID(uuidString: $0.lessonID) })
        guard !lessonIDs.isEmpty else { return [:] }
        
        let allLessons: [Lesson] = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        let lessons = allLessons.filter { lessonIDs.contains($0.id) }
        var byID: [UUID: Lesson] = [:]
        for lesson in lessons {
            byID[lesson.id] = lesson
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
