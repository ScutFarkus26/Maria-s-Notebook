import Foundation
import CoreData
import os

// MARK: - Project Check-In Work Repair

nonisolated extension DataCleanupService {

    /// Stamps `sourceContextType = .projectSession` on check-in work that
    /// names a project check-in but was saved without the type.
    ///
    /// Until 2026-10-11 a check-in made in Uniform mode gave each child's
    /// follow-up its check-in's id (`sourceContextID`) but not the type, and
    /// every project reader filters on both: the project and the check-in
    /// showed none of that work, and deleting the project left it on the
    /// children (bug hunt 2026-10-11 #65). Only a row whose type is empty and
    /// whose context id is a project check-in's id is touched; a typed row,
    /// or an id naming no check-in, is left alone. It only fills an empty
    /// field, so a second run finds nothing, and two devices write the same
    /// value. Projects are the guide's own records (private store), so this
    /// never touches the classroom share.
    ///
    /// Returns how many work rows it changed. Synchronous, on `context`'s
    /// queue; it doesn't save.
    @discardableResult
    static func repairProjectWorkContextType(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "(sourceContextTypeRaw == nil OR sourceContextTypeRaw == '') "
                + "AND sourceContextID != nil AND sourceContextID != ''"
        )
        let candidates = context.safeFetch(request).filter { !$0.isDeleted }
        let contextIDs = Set(candidates.compactMap { $0.sourceContextID.flatMap(UUID.init(uuidString:)) })
        guard !contextIDs.isEmpty else { return 0 }

        let sessionRequest = CDFetchRequest(CDProjectSession.self)
        sessionRequest.predicate = NSPredicate(format: "id IN %@", Array(contextIDs))
        let sessionIDs = Set(context.safeFetch(sessionRequest).compactMap(\.id))
        guard !sessionIDs.isEmpty else { return 0 }

        var changed = 0
        for work in candidates {
            guard let contextID = work.sourceContextID.flatMap(UUID.init(uuidString:)),
                  sessionIDs.contains(contextID) else { continue }
            work.sourceContextType = .projectSession
            changed += 1
        }
        if changed > 0 {
            logger.info("Marked \(changed, privacy: .public) project check-in work row(s) as project work")
        }
        return changed
    }

    /// Runs `repairProjectWorkContextType` once on this device, from the launch
    /// pass: never while the first download from iCloud is under way
    /// (`FirstDownloadGate`), since check-ins still on their way down would
    /// leave their work unmatched, and never on a pass whose earlier steps left
    /// changes they couldn't save. It saves its own changes, and counts as done
    /// only once they're saved. Every device runs it; it only fills an empty
    /// field, with the same value everywhere, so two devices converge.
    ///
    /// Returns how many rows it changed, or nil when it didn't run or couldn't save.
    @discardableResult
    static func repairProjectWorkContextTypeIfDue(
        using context: NSManagedObjectContext,
        firstDownloadPending: Bool,
        defaults: UserDefaults = .standard
    ) -> Int? {
        let flag = UserDefaultsKeys.projectWorkContextRepairDone
        guard !firstDownloadPending, !defaults.bool(forKey: flag), !context.hasChanges else { return nil }
        let changed = repairProjectWorkContextType(using: context)
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return nil
        }
        defaults.set(true, forKey: flag)
        return changed
    }
}
