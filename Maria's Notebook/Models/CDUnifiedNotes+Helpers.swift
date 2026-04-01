import Foundation
import CoreData

// MARK: - CDNote Legacy Field Upsert

extension CDNote {
    /// Upserts a legacy-field note: creates, updates, or deletes as needed.
    /// - Parameters:
    ///   - text: The note body text; nil or empty deletes existing legacy notes.
    ///   - tags: Tags to assign on creation.
    ///   - scope: The NoteScope to use.
    ///   - existingNotes: The NSSet of existing CDNote objects from the parent relationship.
    ///   - context: The NSManagedObjectContext.
    ///   - attach: Closure to attach the newly created note to its parent (e.g., `note.attendanceRecord = self`).
    /// - Returns: `true` if a change was made.
    @discardableResult
    static func upsertLegacyFieldNote(
        text: String?,
        tags: [String] = [],
        scope: NoteScope,
        existingNotes: NSSet?,
        context: NSManagedObjectContext,
        attach: (CDNote) -> Void
    ) -> Bool {
        let trimmed = text?.trimmed() ?? ""
        let allNotes = (existingNotes?.allObjects as? [CDNote]) ?? []
        let legacyNotes = allNotes.filter { $0.reportedBy == LegacyNoteFieldConstants.reporter }

        if trimmed.isEmpty {
            guard !legacyNotes.isEmpty else { return false }
            for note in legacyNotes {
                context.delete(note)
            }
            return true
        }

        if let note = legacyNotes.sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }).first {
            if note.body == trimmed { return false }
            note.body = trimmed
            note.updatedAt = Date()
            return true
        }

        let note = CDNote(context: context)
        note.body = trimmed
        note.scope = scope
        note.tagsArray = tags
        note.reportedBy = LegacyNoteFieldConstants.reporter
        note.reporterName = LegacyNoteFieldConstants.reporterName
        attach(note)
        return true
    }
}

// MARK: - setLegacyNoteText on CD entities

extension CDAttendanceRecord {
    var latestUnifiedNoteText: String {
        let allNotes = (notes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        let studentUUID = UUID(uuidString: studentID)
        let scope: NoteScope = studentUUID.map { .student($0) } ?? .all
        return CDNote.upsertLegacyFieldNote(
            text: text,
            tags: [TagHelper.tagFromNoteCategory("attendance")],
            scope: scope,
            existingNotes: notes,
            context: context
        ) { note in
            note.attendanceRecord = self
        }
    }
}

extension CDProjectSession {
    var latestUnifiedNoteText: String {
        let allNotes = (noteItems?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: noteItems,
            context: context
        ) { note in
            note.projectSession = self
        }
    }
}

extension CDReminder {
    var latestUnifiedNoteText: String {
        let allNotes = (noteItems?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: noteItems,
            context: context
        ) { note in
            note.reminder = self
        }
    }
}

extension CDWorkModel {
    var latestUnifiedNoteText: String {
        let allNotes = (unifiedNotes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: unifiedNotes,
            context: context
        ) { note in
            note.work = self
        }
    }
}

extension CDWorkCheckIn {
    var latestUnifiedNoteText: String {
        let allNotes = (notes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        let scope: NoteScope
        if let work {
            let parts = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            let studentUUIDs = parts.compactMap { UUID(uuidString: $0.studentID) }
            if studentUUIDs.count == 1, let only = studentUUIDs.first {
                scope = .student(only)
            } else if studentUUIDs.count > 1 {
                scope = .students(studentUUIDs)
            } else if let studentUUID = UUID(uuidString: work.studentID) {
                scope = .student(studentUUID)
            } else {
                scope = .all
            }
        } else {
            scope = .all
        }

        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: notes,
            context: context
        ) { note in
            note.workCheckIn = self
        }
    }
}

extension CDWorkCompletionRecord {
    var latestUnifiedNoteText: String {
        let allNotes = (notes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        let scope: NoteScope
        if let studentUUID = UUID(uuidString: studentID) {
            scope = .student(studentUUID)
        } else {
            scope = .all
        }

        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: notes,
            context: context
        ) { note in
            note.workCompletionRecord = self
        }
    }
}

extension CDStudentTrackEnrollmentEntity {
    var latestUnifiedNoteText: String {
        CDNote.latestBody(in: richNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        let scope: NoteScope
        if let studentUUID = UUID(uuidString: studentID) {
            scope = .student(studentUUID)
        } else {
            scope = .all
        }

        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: NSSet(array: richNotes),
            context: context
        ) { note in
            note.studentTrackEnrollment = self
        }
    }
}

extension CDSchoolDayOverride {
    var latestUnifiedNoteText: String {
        CDNote.latestBody(in: notes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: NSSet(array: notes),
            context: context
        ) { note in
            note.schoolDayOverride = self
        }
    }
}

// MARK: - Helper

extension CDNote {
    static func latestNote(in notes: [CDNote], preferredReporter: String? = nil) -> CDNote? {
        if let preferredReporter {
            let preferred = notes.filter { $0.reportedBy == preferredReporter }
            if let newest = preferred.sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }).first {
                return newest
            }
        }
        return notes.sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }).first
    }

    static func latestBody(in notes: [CDNote], preferredReporter: String? = nil) -> String {
        latestNote(in: notes, preferredReporter: preferredReporter)?.body ?? ""
    }
}

// MARK: - syncStudentLinks

extension CDNote {
    /// Syncs the studentLinks relationship to match the current scope.
    /// Creates NoteStudentLink entries for `.students([UUID])` scope.
    func syncStudentLinks(in context: NSManagedObjectContext) {
        // Clear existing links
        if let existingLinks = studentLinks?.allObjects as? [CDNoteStudentLink] {
            for link in existingLinks {
                context.delete(link)
            }
        }

        // Create new links for multi-student scope
        if case .students(let studentUUIDs) = scope {
            for uuid in studentUUIDs {
                let link = CDNoteStudentLink(context: context)
                link.studentID = uuid.uuidString
                link.note = self
            }
        }
    }
}
