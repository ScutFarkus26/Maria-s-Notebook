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

    var id: NSManagedObjectID { assignment.objectID }
}

/// New work for one lesson and these children.
struct ChecklistWorkTarget: Identifiable {
    let id = UUID()
    let lessonID: UUID
    let studentIDs: Set<UUID>
    /// Made from the selection bar, so closing the sheet also clears the selection.
    let fromSelection: Bool
}
