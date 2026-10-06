import CoreData
import Foundation

// What the guide reads before confirming "Remove Last Year from the Share": the plan,
// described, and the checks a plan made again just before the run must pass.

extension ClassroomShareRelease {

    /// A child leaving the share, with how many marks go with her.
    struct DepartingChild: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let departed: Date?
        let attendanceRecords: Int
    }

    /// A shared record from before this school year that stays in the share, because a
    /// backup can't hold it (`BackupGap`): named in the preview so the count adds up.
    struct LeftShared: Sendable, Equatable, Identifiable {
        let id: NSManagedObjectID
        let entity: String
        let gap: BackupGap
        /// The child it is about, when there is one to name.
        let childName: String?
        let date: Date?
    }

    /// What pressing the button would do, for the guide to read before confirming.
    struct Preview: Sendable, Equatable {
        /// The school year's first day: everything from it on stays shared.
        let cutoff: Date
        /// Children leaving the share, with how many marks go with each.
        let children: [DepartingChild]
        /// Earlier-year attendance of children in this year's class.
        let olderAttendance: Int
        /// Earlier-year attendance of children who aren't (they left earlier, or their
        /// record is gone) and aren't leaving the share in this run.
        let olderAttendanceOfChildrenWhoLeft: Int
        /// Records a stopped run left on both sides; this run finishes them.
        let unfinished: Int
        /// Records that stay shared because a backup can't hold them.
        let leftShared: [LeftShared]
        let batches: [Batch]

        var isEmpty: Bool { batches.isEmpty }
        var recordCount: Int { batches.reduce(0) { $0 + $1.moves.count } }
        /// Every record the run touches: each shared original, and any private copy a
        /// stopped run left. The backup must hold each one (`checkBackup`).
        var records: [NSManagedObjectID] { ClassroomShareRelease.records(in: batches) }
    }

    nonisolated static func records(in batches: [Batch]) -> [NSManagedObjectID] {
        batches.flatMap(\.moves).flatMap { move in move.sharedRows + [move.existingTwin].compactMap { $0 } }
    }

    // MARK: - Reading

    /// Reads the store and plans the release. Nil when the share can't be read.
    @MainActor
    static func preview(coreDataStack: CoreDataStack) async throws -> Preview? {
        guard let store = coreDataStack.privatePersistentStore,
              let pinned = CDClassroomMembership.pinnedZoneName(in: coreDataStack.viewContext) else { return nil }
        let scope = ClassroomShareScope()
        let container = coreDataStack.container
        let rows = try await rows(
            container: container, storeID: store.identifier, pinnedZone: pinned, scope: scope,
            environment: .live(container: container)
        )
        return await preview(rows, cutoff: scope.cutoff, container: container)
    }

    /// The preview of `rows`: planned, and described from `container`'s store.
    static func preview(_ rows: [Row], cutoff: Date, container: NSPersistentCloudKitContainer) async -> Preview {
        let batches = plan(rows)
        let unfinished = batches.flatMap(\.moves).filter { $0.existingTwin != nil }.count
        // Earlier-year marks not going with a departing child: of children in this year's
        // class, or of children who aren't (they left earlier, or their record is gone).
        let inClass = Set(rows.filter { $0.entity == "Student" && $0.belongs }.map(\.studentKey))
        let olderMoves = batches.filter { $0.studentKey == nil }.flatMap(\.moves)
        let older = olderMoves.filter { inClass.contains($0.studentKey) }.count
        let described = await describe(batches, leftShared: leftShared(in: rows), container: container)
        return Preview(
            cutoff: cutoff, children: described.children, olderAttendance: older,
            olderAttendanceOfChildrenWhoLeft: olderMoves.count - older, unfinished: unfinished,
            leftShared: described.leftShared, batches: batches
        )
    }

    @concurrent
    private static func describe(
        _ batches: [Batch], leftShared: [Row], container: NSPersistentCloudKitContainer
    ) async -> (children: [DepartingChild], leftShared: [LeftShared]) {
        let context = container.newBackgroundContext()
        return await context.perform {
            let children = batches.compactMap { batch -> DepartingChild? in
                guard let key = batch.studentKey,
                      let studentMove = batch.moves.first(where: { $0.entity == "Student" }),
                      let student = try? context.existingObject(with: studentMove.source) as? CDStudent
                else { return nil }
                return DepartingChild(
                    id: key, name: student.fullName, departed: student.dateWithdrawn,
                    attendanceRecords: batch.moves.filter { $0.entity == "AttendanceRecord" }.count
                )
            }
            .sorted { $0.name < $1.name }
            return (children, describeLeftShared(leftShared, in: context))
        }
    }

    /// On `context`'s queue: each record left shared, with its child's name and its date.
    nonisolated private static func describeLeftShared(
        _ rows: [Row], in context: NSManagedObjectContext
    ) -> [LeftShared] {
        let keys = Set(rows.compactMap { UUID(uuidString: $0.studentKey) })
        var names: [String: String] = [:]
        if !keys.isEmpty {
            let request = NSFetchRequest<CDStudent>(entityName: "Student")
            request.predicate = NSPredicate(format: "id IN %@", Array(keys))
            for student in (try? context.fetch(request)) ?? [] {
                guard let id = student.id?.uuidString else { continue }
                names[ClassroomShareScope.normalizedID(id)] = student.fullName
            }
        }
        return rows.compactMap { row -> LeftShared? in
            guard let gap = row.backupGap, let object = try? context.existingObject(with: row.objectID) else {
                return nil
            }
            let isStudent = row.entity == "Student"
            return LeftShared(
                id: row.objectID, entity: row.entity, gap: gap,
                childName: isStudent ? (object as? CDStudent)?.fullName : names[row.studentKey],
                date: isStudent ? nil : object.value(forKey: "date") as? Date
            )
        }
    }

    // MARK: - Checked again before the run

    /// Why `fresh`, planned again once the backup is made, isn't what the guide confirmed
    /// (`confirmed`), in her words, or nil. Another school-year start (synced from another
    /// device, or set over MCP while the sheet was open) would move this year's first weeks
    /// out of the share; records the preview didn't hold weren't shown to her. Fewer records
    /// (some finished or deleted meanwhile) is no reason to stop.
    static func changeSincePreview(_ fresh: Preview, confirmed: Preview) -> String? {
        if fresh.cutoff != confirmed.cutoff {
            let start = fresh.cutoff.formatted(.dateTime.weekday(.wide).month(.wide).day())
            return "The school-year start changed to \(start) while this was open, so nothing was removed. "
                + "Check what would leave below, then try again."
        }
        let shown = Set(confirmed.records)
        if fresh.records.contains(where: { !shown.contains($0) }) {
            return "More from before this school year reached the share while this was open, so nothing "
                + "was removed. Check what would leave below, then try again."
        }
        return nil
    }

    /// The start-date check: attendance taken in the two weeks before `cutoff` means the
    /// school-year start is set later than the first day school met, and releasing now would
    /// take this year's first marks out of the share. The reason in the guide's words, or nil.
    static func cutoffBlocker(_ cutoff: Date, context: NSManagedObjectContext, store: NSPersistentStore?) -> String? {
        let scope = ClassroomShareScope(cutoff: cutoff)
        guard let early = scope.attendanceJustBeforeCutoff(in: context, store: store) else { return nil }
        let day = early.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let start = scope.cutoff.formatted(.dateTime.month(.wide).day())
        return "Attendance was taken on \(day), before your school-year start (\(start)). "
            + "Set the start to the first day of school in Settings › School year, then come back."
    }

    // MARK: - One run at a time

    /// Whether a release, or the finishing of a stopped one, is running in this process.
    /// Two at once could each delete the other's original and leave a record with no copy:
    /// a second sheet (another window, the iPad rehearsal's) must wait. Observable, so
    /// Settings' card says it's running rather than offering to finish it.
    @Observable @MainActor
    final class RunState {
        fileprivate(set) var isRunning = false
    }

    @MainActor static let runState = RunState()

    @MainActor static var isRunning: Bool { runState.isRunning }

    static let runningMessage = "Removing last year is already running in another window. Wait for it to finish."

    /// Claims the run for this process: false when one is already running.
    @MainActor
    static func claimRun() -> Bool {
        guard !runState.isRunning else { return false }
        runState.isRunning = true
        return true
    }

    @MainActor
    static func endRun() {
        runState.isRunning = false
    }
}
