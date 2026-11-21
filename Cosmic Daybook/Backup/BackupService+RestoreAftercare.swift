// BackupService+RestoreAftercare.swift
// What a restore does around its records: the student links its notes need,
// the denormalized day it repairs after saving, the fills it runs once saved,
// the album warning it gives, how it says it failed after its save, and its
// wait for iCloud.

import CoreData
import Foundation
import OSLog

/// A restore that failed after its records were saved: the store holds the
/// restore, so a replace restore goes back to its checkpoint
/// (`BackupTransactionManager.executeWithRollback`). A failure before the
/// save leaves the notebook as it was, and nothing is rolled back.
nonisolated struct BackupRestoreSavedError: LocalizedError {
    let underlying: any Error

    var errorDescription: String? { (underlying as? any LocalizedError)?.errorDescription }
}

/// One step every restore runs on the notebook once its records are saved:
/// a fill that stamps a field the restored rows left unset (an older backup's
/// rows lack it, and so does a record restored without it), or a tidy-up of
/// fields that go in pairs. Each keys on what it finds (a nil, an odd pair),
/// never on a one-time flag, so the same step can run at every launch too
/// and a second run changes nothing (plan "Domain logic fixes", Decision 19).
nonisolated struct BackupRestoreFill: Sendable {
    /// What the log calls it.
    let name: String
    /// Changes records in the context; `runAfterRestoreFills` saves once
    /// after every fill. `formatVersion` is the restored backup's.
    let run: @MainActor @Sendable (_ context: NSManagedObjectContext, _ formatVersion: Int) -> Void
}

extension BackupService {

    // MARK: - After-Restore Fills

    /// Every restore's fills, in the order they run. A fill joins by its line
    /// here, beside the launch step that runs the same code: the work
    /// assignment fill and the guardian person fill of plan "Domain logic
    /// fixes" each add one.
    static let afterRestoreFills: [BackupRestoreFill] = [
        // A restore writes a mark's fields one by one, so an odd pair (a
        // present mark with an old "Sick") is put right as the store writes
        // it (domain-logic review A13).
        BackupRestoreFill(name: "attendance pairs") { context, _ in
            CDAttendanceRecord.normalizeAll(in: context)
        },
        // A format-46 backup's work rows carry no assignment, and a row can
        // be restored without one: each gets its `assignmentID` and
        // `isSharedRow` from the guess, as at launch (domain-logic review R22).
        BackupRestoreFill(name: "work assignments") { context, _ in
            _ = WorkAssignmentFill.run(in: context)
        },
        // A backup can hold two lessons on one step of a sub-area: it is
        // numbered in the one lesson order, as at launch (domain-logic review R21).
        BackupRestoreFill(name: "lesson order ties") { context, _ in
            LessonOrder.renumberTies(in: context.safeFetch(CDFetchRequest(CDLesson.self)))
        }
        // Year-plan entries are put right at the next launch and when her plan
        // opens (`YearPlanEntryRepair`), not here, so a restore brings each
        // entry back as it was backed up.
    ]

    /// Runs `fills` on `context`, then saves what they changed: once the
    /// restore's own save is done, so a fill sees every restored record.
    /// Returns false when the save failed; what the fills changed is then
    /// rolled back, and since each keys on what it finds, the next launch or
    /// restore fills it again. Nothing runs while the context holds someone
    /// else's unsaved change, which the save would commit with it.
    @discardableResult
    func runAfterRestoreFills(
        _ fills: [BackupRestoreFill] = BackupService.afterRestoreFills,
        formatVersion: Int,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard !fills.isEmpty else { return true }
        guard !context.hasChanges else {
            Logger.backup.warning("Skipped the after-restore fills: the notebook had unsaved changes")
            return false
        }
        for fill in fills {
            fill.run(context, formatVersion)
        }
        guard context.safeSave() else {
            context.rollback()
            let names = fills.map(\.name).joined(separator: ", ")
            Logger.backup.error("The after-restore fills couldn't be saved (\(names, privacy: .public))")
            return false
        }
        return true
    }

    // MARK: - Album Reattachment

    /// Album bookmarks, notes, highlights, and ink key on the album PDF's
    /// filename. They restore intact, but on a device with no album folder
    /// registered they have nothing to attach to until the guide adds one —
    /// say so, rather than letting them look lost. `albumIDs` holds every
    /// album the restored bookmarks, page notes, highlights, ink and reading
    /// positions name (`BackupRestoreRun.albumIDs`).
    func albumReattachWarning(for albumIDs: Set<String>) -> String? {
        guard !albumIDs.isEmpty, !AlbumLibrary.hasResolvableFolderBookmark() else { return nil }
        let noun = albumIDs.count == 1 ? "album" : "albums"
        return "This backup includes bookmarks, notes, highlights, or drawings for "
            + "\(albumIDs.count) \(noun). Open Albums and add your album folder to reattach them."
    }

    // MARK: - Denormalized Fields

    func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(
            CDFetchRequest(CDLessonAssignment.self)
        )
        var repairedCount = 0
        for la in assignmentsForRepair {
            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try viewContext.save()
        }
    }
}

extension BackupRestoreRun {

    /// Gives each restored note the student links its scope calls for, as
    /// every note writer does (`CDNote.syncStudentLinks`), without dropping
    /// any link the backup carries. A merge restore that changed a note's
    /// scope left the links of its old scope beside the backup's (so the note
    /// still showed under a child it no longer names), and a backup without a
    /// note's links left it with none (so it showed under no one).
    ///
    /// - A link this device had that the restored scope doesn't name is
    ///   removed; one the backup carries stays, as every backed-up row does.
    /// - A child with more than one link keeps one, the one `syncStudentLinks`
    ///   keeps (`CDNoteStudentLink.keeper`), so every device keeps the same.
    ///   A merge kept both the device's link and the backup's under another
    ///   id, so the note named the child twice (bug hunt 2026-10-29).
    /// - A child a multi-child scope names but no link covers gets one, with
    ///   the id every device gives it.
    func matchStudentLinksToScope() throws {
        for id in restoredNoteIDs {
            guard let note = try index.related(CDNote.self, id: id) else { continue }
            let (named, linkedByScope) = Self.studentsNamed(by: note.scope)
            var linksByStudent: [String: [CDNoteStudentLink]] = [:]
            for link in note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? [] where !link.isDeleted {
                linksByStudent[link.studentID.uppercased(), default: []].append(link)
            }
            for (student, links) in linksByStudent {
                // A child the scope doesn't name stays only by a link the backup carries.
                let candidates = named.contains(student)
                    ? links : links.filter { $0.id.map(restoredLinkIDs.contains) == true }
                let keeper = CDNoteStudentLink.keeper(of: candidates, stableID: stableLinkID(note, student))
                for link in links where link !== keeper {
                    context.delete(link)
                }
            }
            for student in linkedByScope where linksByStudent[student.uuidString.uppercased()] == nil {
                let link = CDNoteStudentLink(context: context)
                if let noteID = note.id { link.id = CDNoteStudentLink.stableID(noteID: noteID, studentID: student) }
                link.noteID = note.id?.uuidString ?? ""
                link.studentID = student.uuidString
                link.note = note
            }
        }
    }

    /// The id every device gives `note`'s link to `student` (an uppercased
    /// id), when both ids are whole.
    private func stableLinkID(_ note: CDNote, _ student: String) -> UUID? {
        guard let noteID = note.id, let studentID = UUID(uuidString: student) else { return nil }
        return CDNoteStudentLink.stableID(noteID: noteID, studentID: studentID)
    }

    /// The children a scope names (uppercased ids), and those it gives a
    /// link each: only a multi-child scope does (`syncStudentLinks`), but a
    /// one-child note's link to its child is no stray.
    private static func studentsNamed(by scope: NoteScope) -> (named: Set<String>, linked: [UUID]) {
        switch scope {
        case .all: ([], [])
        case .student(let student): ([student.uuidString.uppercased()], [])
        case .students(let students): (Set(students.map { $0.uuidString.uppercased() }), students)
        }
    }
}

/// Outcome of waiting for `NSPersistentCloudKitContainer` to finish the post-restore export.
nonisolated enum CloudExportWaitResult: Sendable {
    /// No CloudKit-backed store, or the wait completed and a `.export` event succeeded.
    case completed
    /// `.export` event arrived but reported `succeeded == false`. Carries a localized description
    /// (not the underlying `Error` — `any Error` doesn't cross task boundaries cleanly).
    case failed(reason: String?)
    /// Timed out before any complete `.export` event arrived. Sync is still running in the background.
    case timedOut
}

// MARK: - CloudKit Export Wait

/// What a restore hears from iCloud about its export, listened for from
/// before its save (bug hunt 2026-11-02, #23). The observer is added as
/// `listening` returns, so a quick export that finishes during the save is
/// buffered for the wait. A `NotificationCenter.messages` sequence would not
/// do: it starts listening only when it is first iterated, which is after
/// the save. `stop()` removes the observer; call it when the restore ends.
///
/// Each finished export comes with when it started, so the wait counts only
/// one that started once the restore had saved (`awaitCloudKitExport`): an
/// export of the edits saved just before the restore
/// (`saveEditsMadeBeforeRestore`) can finish during the restore's save, and
/// was taken for the restore's (2026-11-03 review).
nonisolated struct CloudExportListener: Sendable {
    /// A finished export: when it started, and how it went.
    struct Export: Sendable {
        let startedAt: Date
        let result: CloudExportWaitResult
    }

    /// The finished exports, in the order they were posted.
    let results: AsyncStream<Export>
    /// False when the restore has no export to wait for: nothing is observed.
    let waits: Bool
    let stop: @Sendable () -> Void

    /// Starts listening for `name` on `center` as it returns, when `waits`.
    /// `result` reads a notification: a finished export, or nil to keep
    /// listening. The observer is formed here, outside the main actor,
    /// because CloudKit posts its events on its own queue.
    static func listening(
        on center: NotificationCenter = .default,
        to name: Notification.Name = NSPersistentCloudKitContainer.eventChangedNotification,
        waits: Bool,
        result: @escaping @Sendable (Notification) -> Export? = CloudExportListener.exportResult
    ) -> CloudExportListener {
        let (results, continuation) = AsyncStream<Export>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        guard waits else {
            continuation.finish()
            return CloudExportListener(results: results, waits: false) {}
        }
        let observer = center.addObserver(forName: name, object: nil, queue: nil) { note in
            if let finished = result(note) { continuation.yield(finished) }
        }
        // The token is only handed back to the center that made it.
        nonisolated(unsafe) let token = observer
        return CloudExportListener(results: results, waits: true) {
            center.removeObserver(token)
            continuation.finish()
        }
    }

    /// A CloudKit event notification's export when it is a finished one;
    /// nil for imports, setups and exports still running.
    static func exportResult(_ note: Notification) -> Export? {
        let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
              event.type == .export, event.endDate != nil else { return nil }
        return Export(
            startedAt: event.startDate,
            result: event.succeeded ? .completed : .failed(reason: event.error?.localizedDescription)
        )
    }
}

extension BackupService {
    /// Listens for the export of a restore into `viewContext`, from now: the
    /// restore makes it before its save. Waits for nothing unless the restore
    /// went into the app's notebook while it syncs: in-memory tests, iCloud
    /// sync off, the local-only fallback and the database-error screen's
    /// fresh notebook (`FreshNotebookRestore`) never export, and would only
    /// wait 30 seconds to say sync is "still running in the background".
    func cloudExportListener(for viewContext: NSManagedObjectContext) -> CloudExportListener {
        CloudExportListener.listening(waits: BackupRestoreScope.syncsWithICloud(viewContext))
    }

    /// Waits for the first finished export `listener` heard that started at
    /// or after `savedAt` (the restore's save), up to `timeout`; at once
    /// when the restore has none to wait for. An export that started before
    /// the save, however late it finished, doesn't carry the restore, as
    /// `UnsentChangesKeepAlive` judges it.
    func awaitCloudKitExport(
        _ listener: CloudExportListener,
        startedFrom savedAt: Date,
        timeout: Duration
    ) async -> CloudExportWaitResult {
        guard listener.waits else { return .completed }
        let results = listener.results
        return await withTaskGroup(of: CloudExportWaitResult.self) { group in
            group.addTask {
                for await export in results where export.startedAt >= savedAt {
                    return export.result
                }
                return .timedOut
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }
}
