import CoreData
import CryptoKit
import Foundation

// MARK: - CDNote Legacy Field Upsert

nonisolated extension CDNote {
    /// Upserts a legacy-field note: creates, updates, or deletes as needed.
    /// - Parameters:
    ///   - text: The note body text; nil or empty deletes existing legacy notes.
    ///   - tags: Tags to assign on creation.
    ///   - scope: The NoteScope to use.
    ///   - existingNotes: The NSSet of existing CDNote objects from the parent relationship.
    ///   - context: The NSManagedObjectContext.
    ///   - attach: Closure to attach the newly created note to its parent (e.g., `note.work = self`).
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

        if let note = legacyNotes
            .sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
            .first {
            if note.body == trimmed { return false }
            note.body = trimmed
            note.updatedAt = Date()
            // A group check-in's note written before its links were kept gets
            // them here (2026-10-10).
            note.syncStudentLinks(in: context)
            return true
        }

        let note = CDNote(context: context)
        note.body = trimmed
        note.scope = scope
        note.tagsArray = tags
        note.reportedBy = LegacyNoteFieldConstants.reporter
        note.reporterName = LegacyNoteFieldConstants.reporterName
        attach(note)
        // A note about several children shows on their Notes tabs only through
        // its links; without them a group check-in's note showed on none.
        note.syncStudentLinks(in: context)
        return true
    }
}

// MARK: - setLegacyNoteText on CD entities
//
// `latestUnifiedNoteText` is the newest note of any kind, for display.
// `legacyNoteText` is the record's own field note, the one
// `setLegacyNoteText` writes: an edit field that saves through
// `setLegacyNoteText` starts from it. Started from the newest note, saving the
// field, even unchanged, overwrote the field note with an observation's words,
// and clearing it deleted the field note (2026-10-05).

nonisolated extension CDProjectSession {
    var latestUnifiedNoteText: String {
        let allNotes = (noteItems?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    var legacyNoteText: String {
        CDNote.legacyFieldBody(in: (noteItems?.allObjects as? [CDNote]) ?? [])
    }

    /// A session's note is about the project's members. It was scoped to the
    /// whole class until 2026-10-10, so it showed on every child's Notes tab;
    /// `.all` remains only for a project with no members.
    @discardableResult
    func setLegacyNoteText(_ text: String?, in context: NSManagedObjectContext) -> Bool {
        return CDNote.upsertLegacyFieldNote(
            text: text,
            scope: NoteScope.forSelection(Set(project?.memberStudentUUIDs ?? [])),
            existingNotes: noteItems,
            context: context
        ) { note in
            note.projectSession = self
        }
    }
}

nonisolated extension CDReminder {
    var latestUnifiedNoteText: String {
        let allNotes = (noteItems?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }
}

nonisolated extension CDWorkModel {
    var latestUnifiedNoteText: String {
        let allNotes = (unifiedNotes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    var legacyNoteText: String {
        CDNote.legacyFieldBody(in: (unifiedNotes?.allObjects as? [CDNote]) ?? [])
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

nonisolated extension CDWorkCheckIn {
    var latestUnifiedNoteText: String {
        let allNotes = (notes?.allObjects as? [CDNote]) ?? []
        return CDNote.latestBody(in: allNotes)
    }

    var legacyNoteText: String {
        CDNote.legacyFieldBody(in: (notes?.allObjects as? [CDNote]) ?? [])
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

nonisolated extension CDWorkCompletionRecord {
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

nonisolated extension CDStudentTrackEnrollmentEntity {
    var latestUnifiedNoteText: String {
        CDNote.latestBody(in: richNotes)
    }
}

// MARK: - Helper

nonisolated extension CDNote {
    static func latestNote(in notes: [CDNote], preferredReporter: String? = nil) -> CDNote? {
        if let preferredReporter {
            let preferred = notes.filter { $0.reportedBy == preferredReporter }
            if let newest = preferred
                .sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
                .first {
                return newest
            }
        }
        return notes.sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }).first
    }

    static func latestBody(in notes: [CDNote], preferredReporter: String? = nil) -> String {
        latestNote(in: notes, preferredReporter: preferredReporter)?.body ?? ""
    }

    /// The body of the field note `upsertLegacyFieldNote` would write (the
    /// newest legacy-field note), or "" when there is none.
    static func legacyFieldBody(in notes: [CDNote]) -> String {
        latestNote(in: notes.filter { $0.reportedBy == LegacyNoteFieldConstants.reporter })?.body ?? ""
    }
}

// MARK: - syncStudentLinks

nonisolated extension CDNote {
    /// Makes the note's student links match its scope: one link per child a
    /// multi-child scope names, none for any other scope.
    ///
    /// **A diff, never delete-and-recreate.** Each link is a synced row. Until
    /// 2026-10-10 every call deleted all the links and made new ones, so two
    /// devices saving (or repairing) the same note each made their own set,
    /// both sets synced, and the note had every child linked twice. Now a link
    /// that's already right stays; a child with no link gets one, and a child
    /// the scope no longer names loses hers.
    ///
    /// A new link's id comes from the note and the child
    /// (`CDNoteStudentLink.stableID`), so two devices adding the same link make
    /// two rows with one id, which the deduplication folds into one. Where a
    /// child already has links with different ids (doubles from older builds),
    /// one is kept — the stable id if it is among them, otherwise the smallest
    /// id, which every device picks alike — and the rest go. Copies sharing the
    /// keeper's id are left to the deduplication, which agrees across devices
    /// on the record name.
    ///
    /// Writes nothing when the links already match. Returns whether it changed any.
    @discardableResult
    func syncStudentLinks(in context: NSManagedObjectContext) -> Bool {
        let named: [UUID]
        if case .students(let studentUUIDs) = scope {
            named = studentUUIDs
        } else {
            named = []
        }

        var linksByStudent: [String: [CDNoteStudentLink]] = [:]
        for link in (studentLinks?.allObjects as? [CDNoteStudentLink]) ?? [] where !link.isDeleted {
            linksByStudent[link.studentID.uppercased(), default: []].append(link)
        }

        var changed = false
        var kept = Set<String>()
        for student in named {
            let key = student.uuidString.uppercased()
            guard kept.insert(key).inserted else { continue }
            let stableID = id.map { CDNoteStudentLink.stableID(noteID: $0, studentID: student) }
            guard let links = linksByStudent[key], !links.isEmpty else {
                let link = CDNoteStudentLink(context: context)
                if let stableID { link.id = stableID }
                link.noteID = id?.uuidString ?? ""
                link.studentID = student.uuidString
                link.note = self
                changed = true
                continue
            }
            let keeperID = CDNoteStudentLink.keeper(of: links, stableID: stableID)?.id
            for link in links where link.id != keeperID {
                context.delete(link)
                changed = true
            }
        }
        for (key, links) in linksByStudent where !kept.contains(key) {
            for link in links {
                context.delete(link)
            }
            changed = true
        }
        return changed
    }
}

nonisolated extension CDNoteStudentLink {
    /// The id every device gives the link between one note and one child: the
    /// first 16 bytes of a SHA-256 of the two ids, marked as an RFC 9562
    /// version 8 (custom) UUID. The same note and child give the same id on
    /// every device and every launch.
    static func stableID(noteID: UUID, studentID: UUID) -> UUID {
        let seed = "NoteStudentLink|\(noteID.uuidString)|\(studentID.uuidString)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Which of one child's links on a note to keep: the one with the stable
    /// id if it is there, otherwise the smallest id, a link with no id last.
    /// Every device orders the same links the same way.
    static func keeper(of links: [CDNoteStudentLink], stableID: UUID?) -> CDNoteStudentLink? {
        func rank(_ link: CDNoteStudentLink) -> String {
            guard let id = link.id else { return "2" }
            return (stableID == id ? "0" : "1") + id.uuidString
        }
        return links.min { rank($0) < rank($1) }
    }
}
