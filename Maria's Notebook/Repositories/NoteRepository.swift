//
//  NoteRepository.swift
//  Maria's Notebook
//
//  Repository for Note entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct NoteRepository: SavingRepository {
    typealias Model = Note

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Note by ID
    func fetchNote(id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch multiple Notes with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter notes. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of Note entities matching the criteria
    func fetchNotes(
        predicate: Predicate<Note>? = nil,
        sortBy: [SortDescriptor<Note>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [Note] {
        var descriptor = FetchDescriptor<Note>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch notes for a specific student using search index attributes
    /// - Parameter studentID: The UUID of the student
    /// - Returns: Array of Notes visible to the student (scoped to them or all)
    func fetchNotesForStudent(studentID: UUID) -> [Note] {
        // Fetch notes with direct student scope or all scope
        let directPredicate = #Predicate<Note> { note in
            note.searchIndexStudentID == studentID || note.scopeIsAll
        }
        var notes = fetchNotes(predicate: directPredicate)

        // Also fetch notes that have student links (for multi-student scope)
        // NoteStudentLink stores studentID as String for CloudKit compatibility
        let studentIDString = studentID.uuidString
        let linkDescriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.studentID == studentIDString }
        )
        if let links = try? context.fetch(linkDescriptor) {
            let linkedNotes = links.compactMap { $0.note }
            let existingIds = Set(notes.map { $0.id })
            for linkedNote in linkedNotes where !existingIds.contains(linkedNote.id) {
                notes.append(linkedNote)
            }
        }

        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Create

    /// Phase 3B: Create domain-specific note based on context
    /// This is called alongside old Note creation during dual-write period
    private func createDomainSpecificNote(
        content: String,
        category: NoteCategory,
        scope: NoteScope,
        lesson: Lesson? = nil,
        work: WorkModel? = nil,
        studentLesson: StudentLesson? = nil,
        studentMeeting: StudentMeeting? = nil,
        lessonAssignment: Presentation? = nil,
        attendanceRecord: AttendanceRecord? = nil,
        workCheckIn: WorkCheckIn? = nil,
        workCompletionRecord: WorkCompletionRecord? = nil,
        workPlanItem: WorkPlanItem? = nil,
        projectSession: ProjectSession? = nil,
        communityTopic: CommunityTopic? = nil,
        reminder: Reminder? = nil,
        schoolDayOverride: SchoolDayOverride? = nil,
        studentTrackEnrollment: StudentTrackEnrollment? = nil,
        practiceSession: PracticeSession? = nil,
        issue: Issue? = nil
    ) {
        // Determine primary context and create appropriate domain-specific note
        if let lesson = lesson {
            let lessonNote = LessonNote(
                content: content,
                category: category,
                lesson: lesson,
                scope: scope
            )
            context.insert(lessonNote)
        } else if let work = work {
            let workNote = WorkNote(
                content: content,
                category: category,
                work: work,
                checkInID: workCheckIn?.id.uuidString,
                completionRecordID: workCompletionRecord?.id.uuidString,
                workPlanItemID: workPlanItem?.id.uuidString
            )
            context.insert(workNote)
        } else if let studentLesson = studentLesson {
            // StudentLesson notes: Create one note per student (multi-student lessons)
            for student in studentLesson.students {
                let studentNote = StudentNote(
                    content: content,
                    category: category,
                    student: student,
                    studentLessonID: studentLesson.id.uuidString
                )
                context.insert(studentNote)
            }
        } else if let studentMeeting = studentMeeting {
            // StudentMeeting notes attach to the student (lookup by studentID)
            if let studentUUID = UUID(uuidString: studentMeeting.studentID) {
                let studentDescriptor = FetchDescriptor<Student>(
                    predicate: #Predicate<Student> { $0.id == studentUUID }
                )
                if let student = try? context.fetch(studentDescriptor).first {
                    let studentNote = StudentNote(
                        content: content,
                        category: category,
                        student: student,
                        meetingID: studentMeeting.id.uuidString
                    )
                    context.insert(studentNote)
                }
            }
        } else if let attendanceRecord = attendanceRecord {
            let attendanceNote = AttendanceNote(
                content: content,
                category: category,
                attendance: attendanceRecord
            )
            context.insert(attendanceNote)
        } else if let presentation = lessonAssignment {
            let presentationNote = PresentationNote(
                content: content,
                category: category,
                presentation: presentation,
                scope: scope
            )
            context.insert(presentationNote)
        } else if let projectSession = projectSession {
            let projectNote = ProjectNote(
                content: content,
                category: category,
                projectSession: projectSession
            )
            context.insert(projectNote)
        } else {
            // GeneralNote for all other contexts (or standalone notes)
            let generalNote = GeneralNote(
                content: content,
                category: category,
                scope: scope,
                communityTopicID: communityTopic?.id.uuidString,
                reminderID: reminder?.id.uuidString,
                issueID: issue?.id.uuidString,
                schoolDayOverrideID: schoolDayOverride?.id.uuidString,
                trackEnrollmentID: studentTrackEnrollment?.id.uuidString,
                practiceSessionID: practiceSession?.id.uuidString
            )
            context.insert(generalNote)
        }
    }

    /// Create a new Note (with Phase 3B dual-write to domain-specific types)
    /// - Parameters:
    ///   - body: The note content
    ///   - category: The note category. Defaults to .general
    ///   - scope: The note scope (all, student, or students). Defaults to .all
    ///   - isPinned: Whether the note is pinned. Defaults to false
    ///   - includeInReport: Whether to include in reports. Defaults to false
    ///   - lesson: Optional lesson relationship
    ///   - work: Optional work relationship
    ///   - studentLesson: Optional studentLesson relationship
    ///   - studentMeeting: Optional studentMeeting relationship
    ///   - lessonAssignment: Optional presentation relationship
    ///   - attendanceRecord: Optional attendance relationship
    ///   - workCheckIn: Optional work check-in relationship
    ///   - workCompletionRecord: Optional work completion relationship
    ///   - workPlanItem: Optional work plan item relationship
    ///   - projectSession: Optional project session relationship
    ///   - communityTopic: Optional community topic relationship
    ///   - reminder: Optional reminder relationship
    ///   - schoolDayOverride: Optional school day override relationship
    ///   - studentTrackEnrollment: Optional track enrollment relationship
    ///   - practiceSession: Optional practice session relationship
    ///   - issue: Optional issue relationship
    ///   - imagePath: Optional image path
    ///   - reportedBy: Optional reporter type
    ///   - reporterName: Optional reporter name
    /// - Returns: The created Note entity
    @discardableResult
    func createNote(
        body: String,
        category: NoteCategory = .general,
        scope: NoteScope = .all,
        isPinned: Bool = false,
        includeInReport: Bool = false,
        lesson: Lesson? = nil,
        work: WorkModel? = nil,
        studentLesson: StudentLesson? = nil,
        studentMeeting: StudentMeeting? = nil,
        lessonAssignment: Presentation? = nil,
        attendanceRecord: AttendanceRecord? = nil,
        workCheckIn: WorkCheckIn? = nil,
        workCompletionRecord: WorkCompletionRecord? = nil,
        workPlanItem: WorkPlanItem? = nil,
        projectSession: ProjectSession? = nil,
        communityTopic: CommunityTopic? = nil,
        reminder: Reminder? = nil,
        schoolDayOverride: SchoolDayOverride? = nil,
        studentTrackEnrollment: StudentTrackEnrollment? = nil,
        practiceSession: PracticeSession? = nil,
        issue: Issue? = nil,
        imagePath: String? = nil,
        reportedBy: String? = nil,
        reporterName: String? = nil
    ) -> Note {
        // Create OLD Note (for backward compatibility)
        let note = Note(
            body: body,
            scope: scope,
            isPinned: isPinned,
            category: category,
            includeInReport: includeInReport,
            lesson: lesson,
            work: work,
            studentLesson: studentLesson,
            studentMeeting: studentMeeting,
            imagePath: imagePath,
            reportedBy: reportedBy,
            reporterName: reporterName
        )
        context.insert(note)

        // Sync student links for multi-student scope
        if case .students = scope {
            note.syncStudentLinks(in: context)
        }

        // Phase 3B: DUAL-WRITE - Also create domain-specific note
        createDomainSpecificNote(
            content: body,
            category: category,
            scope: scope,
            lesson: lesson,
            work: work,
            studentLesson: studentLesson,
            studentMeeting: studentMeeting,
            lessonAssignment: lessonAssignment,
            attendanceRecord: attendanceRecord,
            workCheckIn: workCheckIn,
            workCompletionRecord: workCompletionRecord,
            workPlanItem: workPlanItem,
            projectSession: projectSession,
            communityTopic: communityTopic,
            reminder: reminder,
            schoolDayOverride: schoolDayOverride,
            studentTrackEnrollment: studentTrackEnrollment,
            practiceSession: practiceSession,
            issue: issue
        )

        return note
    }

    // MARK: - Update

    /// Update an existing Note's properties
    /// - Parameters:
    ///   - id: The UUID of the note to update
    ///   - body: New body content (optional)
    ///   - category: New category (optional)
    ///   - scope: New scope (optional)
    ///   - isPinned: New pinned status (optional)
    ///   - includeInReport: New report inclusion status (optional)
    /// - Returns: true if update succeeded, false if note not found
    @discardableResult
    func updateNote(
        id: UUID,
        body: String? = nil,
        category: NoteCategory? = nil,
        scope: NoteScope? = nil,
        isPinned: Bool? = nil,
        includeInReport: Bool? = nil
    ) -> Bool {
        guard let note = fetchNote(id: id) else { return false }

        if let body = body {
            note.body = body
        }
        if let category = category {
            note.category = category
        }
        if let scope = scope {
            note.scope = scope
            note.syncStudentLinks(in: context)
        }
        if let isPinned = isPinned {
            note.isPinned = isPinned
        }
        if let includeInReport = includeInReport {
            note.includeInReport = includeInReport
        }

        note.updatedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a Note by ID
    func deleteNote(id: UUID) throws {
        guard let note = fetchNote(id: id) else { return }
        note.deleteAssociatedImage()
        context.delete(note)
        try context.save()
    }
}
