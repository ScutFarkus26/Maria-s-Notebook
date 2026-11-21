// MigrationRunner+DomainFills.swift
// The launch sweep's fills that key on a nil a newer field left behind
// (plan "Domain logic fixes", Decision 19): each runs at every launch outside
// the first download and after every restore
// (`BackupService.afterRestoreFills`), and saves on its own.

import CoreData
import Foundation

extension MigrationRunner {

    /// Work rows with no assignment get one (`WorkAssignmentFill`, after the
    /// check-in repair, which it reads), and a guardian's rows on each of her
    /// children share one `personID` (`GuardianPeople`, domain logic review A9).
    nonisolated static func runDomainFills(using context: NSManagedObjectContext, firstDownloadPending: Bool) {
        WorkAssignmentFill.runIfDue(using: context, firstDownloadPending: firstDownloadPending)
        GuardianPeople.runIfDue(using: context, firstDownloadPending: firstDownloadPending)
    }
}
