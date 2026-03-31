import SwiftUI
import CoreData

/// Wrapper view that provides note editing for WorkCheckIn using UnifiedNoteEditor
struct WorkCheckInNoteEditorWrapper: View {
    let checkIn: WorkCheckIn
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    // Find existing note or create new one
    private var existingNote: Note? {
        ((checkIn.notes?.allObjects as? [CDNote]) ?? []).first
    }
    
    var body: some View {
        UnifiedNoteEditor(
            context: .workCheckIn(checkIn),
            initialNote: existingNote,
            onSave: { _ in
                // Note is automatically saved via relationship
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}
