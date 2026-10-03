//
//  ChecklistSheetTargets.swift
//  Cosmic Daybook
//
//  The two sheets the checklist opens over the grid: the present-a-lesson sheet for a
//  draft made from the card or the selection, and the new-work sheet for one lesson
//  and some children.
//

import CoreData
import Foundation

/// A draft presentation the checklist made, open in the present-a-lesson sheet.
struct ChecklistPresentationTarget: Identifiable {
    let assignment: CDLessonAssignment
    /// Made from the selection bar, so closing the sheet also clears the selection.
    let fromSelection: Bool
    /// The draft as the checklist made it, so closing the sheet can tell a look from a save.
    let asMade: ChecklistDraftSnapshot

    init(assignment: CDLessonAssignment, fromSelection: Bool) {
        self.assignment = assignment
        self.fromSelection = fromSelection
        self.asMade = ChecklistDraftSnapshot(assignment)
    }

    var id: NSManagedObjectID { assignment.objectID }
}

/// A draft's stored values and attached observations at one moment. The sheet's Save
/// always writes the draft (it stamps `modifiedAt` even when it leaves it in the Inbox),
/// and notes land in `notes` or as observations on it, so a draft that still matches
/// what the checklist made was neither saved nor changed.
struct ChecklistDraftSnapshot {
    private let values: NSDictionary
    private let noteCount: Int

    init(_ draft: CDLessonAssignment) {
        values = Self.values(of: draft)
        noteCount = draft.unifiedNotes?.count ?? 0
    }

    func matches(_ draft: CDLessonAssignment) -> Bool {
        (draft.unifiedNotes?.count ?? 0) == noteCount && Self.values(of: draft) == values
    }

    private static func values(of draft: CDLessonAssignment) -> NSDictionary {
        NSDictionary(dictionary: draft.dictionaryWithValues(forKeys: Array(draft.entity.attributesByName.keys)))
    }
}

/// New work for one lesson and these children.
struct ChecklistWorkTarget: Identifiable {
    let id = UUID()
    let lessonID: UUID
    let studentIDs: Set<UUID>
    /// Made from the selection bar, so closing the sheet also clears the selection.
    let fromSelection: Bool
}
