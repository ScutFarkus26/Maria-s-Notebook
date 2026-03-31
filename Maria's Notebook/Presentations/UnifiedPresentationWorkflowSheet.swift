import SwiftUI
import CoreData
import OSLog

/// Unified split-panel sheet for completing presentations and creating work items in one view.
/// This is a thin wrapper around UnifiedPresentationWorkflowPanel that adds sheet-specific toolbar
struct UnifiedPresentationWorkflowSheet: View {
    // MARK: - Input
    
    let students: [CDStudent]
    let lessonName: String
    let lessonID: UUID
    
    // MARK: - Callbacks
    
    var onComplete: () -> Void
    var onCancel: () -> Void
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var presentationViewModel: PostPresentationFormViewModel
    @State private var triggerCompletion: Bool = false
    
    // MARK: - Init
    
    init(
        students: [CDStudent],
        lessonName: String,
        lessonID: UUID,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let deduped = students.uniqueByID
        self.students = deduped
        self.lessonName = lessonName
        self.lessonID = lessonID
        self.onComplete = onComplete
        self.onCancel = onCancel
        
        _presentationViewModel = State(wrappedValue: PostPresentationFormViewModel(students: deduped))
    }
    
    // MARK: - Body
    
    var body: some View {
        UnifiedPresentationWorkflowPanel(
            presentationViewModel: presentationViewModel,
            students: students,
            lessonName: lessonName,
            lessonID: lessonID,
            onComplete: {
                onComplete()
                dismiss()
            },
            onCancel: {
                onCancel()
                dismiss()
            },
            triggerCompletion: $triggerCompletion
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Complete & Save All") {
                    triggerCompletion = true
                }
                .disabled(!presentationViewModel.canDismiss)
            }
        }
    }
}
