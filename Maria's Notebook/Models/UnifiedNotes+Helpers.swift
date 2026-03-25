import Foundation
import SwiftData

enum LegacyNoteFieldConstants: Sendable {
    nonisolated static let reporter = "legacyField"
    nonisolated static let reporterName = "system"
}

extension Note {
    static func latestNote(in notes: [Note]?, preferredReporter: String? = nil) -> Note? {
        let allNotes = notes ?? []
        if let preferredReporter {
            let preferred = allNotes.filter { $0.reportedBy == preferredReporter }
            if let newest = preferred.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                return newest
            }
        }
        return allNotes.sorted(by: { $0.updatedAt > $1.updatedAt }).first
    }

    static func latestBody(in notes: [Note]?, preferredReporter: String? = nil) -> String {
        latestNote(in: notes, preferredReporter: preferredReporter)?.body ?? ""
    }

    @discardableResult
    static func upsertLegacyFieldNote(
        text: String?,
        tags: [String] = [],
        scope: NoteScope,
        existingNotes: [Note]?,
        context: ModelContext,
        attach: (Note) -> Void
    ) -> Bool {
        let trimmed = text?.trimmed() ?? ""
        let legacyNotes = (existingNotes ?? []).filter { $0.reportedBy == LegacyNoteFieldConstants.reporter }

        if trimmed.isEmpty {
            guard !legacyNotes.isEmpty else { return false }
            for note in legacyNotes {
                context.delete(note)
            }
            return true
        }

        if let note = legacyNotes.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            if note.body == trimmed {
                return false
            }
            note.body = trimmed
            note.updatedAt = Date()
            return true
        }

        let note = Note(
            body: trimmed,
            scope: scope,
            tags: tags,
            reportedBy: LegacyNoteFieldConstants.reporter,
            reporterName: LegacyNoteFieldConstants.reporterName
        )
        attach(note)
        context.insert(note)
        return true
    }
}

extension AttendanceRecord {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: notes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        let studentUUID = UUID(uuidString: studentID)
        let scope: NoteScope = studentUUID.map { .student($0) } ?? .all
        return Note.upsertLegacyFieldNote(
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

extension WorkModel {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: unifiedNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        return Note.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: unifiedNotes,
            context: context
        ) { note in
            note.work = self
        }
    }
}

extension WorkCheckIn {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: notes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        let scope: NoteScope
        if let work {
            let studentUUIDs = (work.participants ?? []).compactMap { UUID(uuidString: $0.studentID) }
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

        return Note.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: notes,
            context: context
        ) { note in
            note.workCheckIn = self
        }
    }
}

extension WorkCompletionRecord {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: notes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        let scope: NoteScope
        if let studentUUID = UUID(uuidString: studentID) {
            scope = .student(studentUUID)
        } else {
            scope = .all
        }

        return Note.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: notes,
            context: context
        ) { note in
            note.workCompletionRecord = self
        }
    }
}

extension ProjectSession {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: noteItems)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        return Note.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: noteItems,
            context: context
        ) { note in
            note.projectSession = self
        }
    }
}

extension StudentTrackEnrollment {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: richNotes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        let scope: NoteScope
        if let studentUUID = UUID(uuidString: studentID) {
            scope = .student(studentUUID)
        } else {
            scope = .all
        }

        return Note.upsertLegacyFieldNote(
            text: text,
            scope: scope,
            existingNotes: richNotes,
            context: context
        ) { note in
            note.studentTrackEnrollment = self
        }
    }
}

extension SchoolDayOverride {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: notes)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        return Note.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: notes,
            context: context
        ) { note in
            note.schoolDayOverride = self
        }
    }
}

extension Reminder {
    var latestUnifiedNoteText: String {
        Note.latestBody(in: noteItems)
    }

    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: ModelContext) -> Bool {
        return Note.upsertLegacyFieldNote(
            text: text,
            scope: .all,
            existingNotes: noteItems,
            context: context
        ) { note in
            note.reminder = self
        }
    }
}
