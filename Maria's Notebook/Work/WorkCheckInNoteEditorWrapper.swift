import SwiftUI
import CoreData

/// Wrapper view that provides note editing for CDWorkCheckIn using UnifiedNoteEditor
struct WorkCheckInNoteEditorWrapper: View {
    let checkIn: CDWorkCheckIn
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    // Find existing note or create new one
    private var existingNote: CDNote? {
        ((checkIn.notes?.allObjects as? [CDNote]) ?? []).first
    }
    
    var body: some View {
        UnifiedNoteEditor(
            context: .workCheckIn(checkIn),
            initialNote: existingNote,
            onSave: { _ in
                // CDNote is automatically saved via relationship
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}
