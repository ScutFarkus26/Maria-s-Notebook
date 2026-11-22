// GuardianPeople.swift
// A parent with two children in the class has a row on each (guardians are
// stored per child). Since schema 25 the rows for one person share a
// `personID` (domain logic review 2026-11-20, A9; plan "Domain logic fixes",
// Decision 12), so an edit on one child's row reaches the sibling's, and
// "receives reports" follows the person.
//
// Rows are matched by email: two rows on different children with the same
// address and the same name (or no name on one of them) are one person.
// Guardians have no phone number to match on. A child with two rows sharing
// an address (a family email both parents use) is left alone, since those
// are two people. Lone rows keep a nil `personID`, which stands for itself.
// The fill keys on the nil (Decision 19), runs at every launch and after
// every restore, and gives a group the id one of its rows already carries,
// else the lowest row id, so two devices write the same value.

import CoreData
import Foundation
import OSLog

nonisolated enum GuardianPeople {

    /// The fields a guardian's edit changes on every row of the person:
    /// everything but the child's own notes and order.
    struct Edit: Equatable {
        var name: String?
        var email: String?
        var relationship: GuardianRelationship?
        var receivesReports: Bool?
        /// The edited row's own notes, which stay on that child's row.
        var notes: String?
    }

    /// Applies `edit` to `guardian` and to every other row with its
    /// `personID`. Stamps `modifiedAt` on each row it changes. Does not save.
    @MainActor
    static func apply(_ edit: Edit, to guardian: CDGuardian) {
        for row in [guardian] + copies(of: guardian) {
            if let name = edit.name { row.name = name }
            if let email = edit.email { row.email = email }
            if let relationship = edit.relationship { row.relationship = relationship }
            if let receivesReports = edit.receivesReports { row.receivesReports = receivesReports }
            if row === guardian, let notes = edit.notes { row.notes = notes }
            row.modifiedAt = Date()
        }
    }

    /// The other rows for the same person: the sibling's copies.
    static func copies(of guardian: CDGuardian) -> [CDGuardian] {
        guard let personID = guardian.personID, !personID.isEmpty,
              let context = guardian.managedObjectContext else { return [] }
        let request = CDFetchRequest(CDGuardian.self)
        request.predicate = NSPredicate(format: "personID == %@", personID)
        return context.safeFetch(request).filter { $0 !== guardian && !$0.isDeleted }
    }

    /// The other children she is a guardian of, through her copies, in the
    /// order the copies sort: "Also Leo's mother".
    static func otherChildren(of guardian: CDGuardian) -> [CDStudent] {
        guard let context = guardian.managedObjectContext else { return [] }
        let ids = copies(of: guardian).map(\.studentID)
            .filter { $0.caseInsensitiveCompare(guardian.studentID) != .orderedSame }
        let uuids = Array(Set(ids.compactMap(UUID.init(uuidString:))))
        guard !uuids.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        var seen = Set<UUID>()
        return context.safeFetch(request)
            .filter { student in student.id.map { seen.insert($0).inserted } ?? false }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    // MARK: - Matching

    /// The key two rows of one person share: the address, folded.
    private static func emailKey(_ row: CDGuardian) -> String? {
        let email = row.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.isEmpty ? nil : email
    }

    private static func nameKey(_ row: CDGuardian) -> String {
        row.name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: nil
        )
    }

    /// Gives `personID` to every row that has none and is one person with a
    /// row on another child. Returns how many rows it changed. On
    /// `context`'s queue; it doesn't save.
    @discardableResult
    static func fill(in context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDGuardian.self)
        request.predicate = NSPredicate(format: "email != nil AND email != ''")
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        guard rows.contains(where: { ($0.personID ?? "").isEmpty }) else { return 0 }

        var changed = 0
        let byAddress = Dictionary(grouping: rows) { emailKey($0) ?? "" }
        for sameAddress in byAddress.values where sameAddress.count > 1 {
            for person in people(in: sameAddress) {
                guard Set(person.map { $0.studentID.uppercased() }).count > 1,
                      person.contains(where: { ($0.personID ?? "").isEmpty }) else { continue }
                let id = personID(for: person)
                for row in person where (row.personID ?? "").isEmpty {
                    row.personID = id
                    row.modifiedAt = Date()
                    changed += 1
                }
            }
        }
        if changed > 0 {
            Logger.database.info("Matched \(changed, privacy: .public) guardian row(s) to the same person")
        }
        return changed
    }

    /// The rows with one address split into people. A child with two rows at
    /// this address can't say which is which, so none of hers join; the rest
    /// join by name, a row with no name joining the one named person.
    private static func people(in sameAddress: [CDGuardian]) -> [[CDGuardian]] {
        let byChild = Dictionary(grouping: sameAddress) { $0.studentID.uppercased() }
        let usable = byChild.values.filter { $0.count == 1 }.flatMap { $0 }
        let named = Dictionary(grouping: usable.filter { !nameKey($0).isEmpty }, by: nameKey)
        var groups = Array(named.values)
        let unnamed = usable.filter { nameKey($0).isEmpty }
        if groups.count == 1 {
            groups[0] += unnamed
        } else if groups.isEmpty {
            groups = [unnamed]
        }
        return groups
    }

    /// The id a person's rows share: one a row already carries (the lowest,
    /// should two disagree), else the lowest row id.
    private static func personID(for rows: [CDGuardian]) -> String {
        if let carried = rows.compactMap(\.personID).filter({ !$0.isEmpty }).min() { return carried }
        return rows.compactMap { $0.id?.uuidString }.min() ?? UUID().uuidString
    }

    /// Matches a row just added or edited in the app with the person it
    /// already belongs to on another child, so it shares her `personID`
    /// from the start. Does not save.
    @MainActor
    static func match(_ guardian: CDGuardian) {
        guard (guardian.personID ?? "").isEmpty, let context = guardian.managedObjectContext else { return }
        fill(in: context)
    }

    /// The launch pass's run: never during the first download from iCloud
    /// (a sibling's row may not have come down yet, and a match is for
    /// good) or after an earlier step left unsaved changes. Saves its own
    /// changes. Returns how many rows it changed, or nil when it didn't run
    /// or couldn't save.
    @discardableResult
    static func runIfDue(using context: NSManagedObjectContext, firstDownloadPending: Bool) -> Int? {
        guard !firstDownloadPending, !context.hasChanges else { return nil }
        let changed = fill(in: context)
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return nil
        }
        return changed
    }
}
