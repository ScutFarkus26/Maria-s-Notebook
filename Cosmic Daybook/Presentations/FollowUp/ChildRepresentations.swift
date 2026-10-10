import CoreData
import Foundation

/// The children whose own follow-up row says the lesson needs presenting to
/// her again, by presentation.
///
/// A presentation's `needsAnotherPresentation` is one flag for everyone on
/// it. A meeting's Re-present is about one child, so it lands on her own
/// `CDLessonPresentation` row and sets the shared flag only when she had the
/// lesson alone (bug hunt 2026-10-09, #12). Readers about one child ask
/// `CDLessonAssignment.needsAnotherPresentation(for:given:)`; a view of the
/// whole group shows the shared flag and names any child flagged here.
///
/// Her row says re-present when its follow-up was resolved as Offer Support
/// or Re-present (a meeting's or a presentation review's Re-present), or is
/// still open with Re-present This Lesson as the support planned.
nonisolated struct ChildRepresentations: Sendable, Equatable {
    /// presentationID → studentIDs, both uuidStrings, uppercased (as
    /// `UUID.uuidString` writes them) so a lowercased one still matches.
    private let studentsByPresentation: [String: Set<String>]

    static let none = ChildRepresentations(studentsByPresentation: [:])

    private init(studentsByPresentation: [String: Set<String>]) {
        self.studentsByPresentation = studentsByPresentation
    }

    /// From rows already fetched; the rows that don't say re-present are skipped.
    init(rows: [CDLessonPresentation]) {
        var byPresentation: [String: Set<String>] = [:]
        for row in rows where !row.isDeleted && Self.saysRepresent(row) {
            guard let presentationID = row.presentationID, !presentationID.isEmpty else { continue }
            byPresentation[presentationID.uppercased(), default: []].insert(row.studentID.uppercased())
        }
        studentsByPresentation = byPresentation
    }

    /// One fetch of just the rows that say re-present: a handful, whatever
    /// the record's size. `presentationIDs` narrows it to those presentations.
    init(presentationIDs: [String]? = nil, in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLessonPresentation.self)
        var predicate = Self.saysRepresentPredicate
        if let presentationIDs {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "presentationID IN %@", presentationIDs), predicate
            ])
        }
        request.predicate = predicate
        self.init(rows: context.safeFetch(request))
    }

    /// The children on `presentationID` whose own row says re-present.
    func students(on presentationID: String) -> Set<String> {
        studentsByPresentation[presentationID.uppercased()] ?? []
    }

    func contains(presentationID: String, studentID: String) -> Bool {
        studentsByPresentation[presentationID.uppercased()]?.contains(studentID.uppercased()) ?? false
    }

    // MARK: - The rule

    static func saysRepresent(_ row: CDLessonPresentation) -> Bool {
        if row.followUpResolvedAt != nil {
            return row.followUpResolutionRaw == PresentationFollowUpResolution.supportOrRepresent.rawValue
        }
        return row.followUpActionRaw == PresentationFollowUpAction.planSupport.rawValue
            && row.followUpSupportRaw == PresentationFollowUpSupport.represent.rawValue
    }

    /// `saysRepresent` as a fetch predicate.
    static var saysRepresentPredicate: NSPredicate {
        NSPredicate(
            format: "(followUpResolvedAt != nil AND followUpResolutionRaw == %@) OR "
                + "(followUpResolvedAt == nil AND followUpActionRaw == %@ AND followUpSupportRaw == %@)",
            PresentationFollowUpResolution.supportOrRepresent.rawValue,
            PresentationFollowUpAction.planSupport.rawValue,
            PresentationFollowUpSupport.represent.rawValue
        )
    }
}
