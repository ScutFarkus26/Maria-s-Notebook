// StudentDetailBottomBar.swift
// Bottom bar component extracted from StudentDetailView

import SwiftUI
import CoreData

struct StudentDetailBottomBar: View {
    let isEditing: Bool
    let selectedSection: StudentWorkspaceSection
    let showDeleteAlert: Binding<Bool>
    let draftFirstName: String
    let draftLastName: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void
    
    var body: some View {
        // Hide the bar if we're not editing and not on overview
        // (only "Done" would show, which is redundant on iPad/Mac)
        if isEditing || selectedSection == .overview {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    if isEditing {
                        editingButtons
                    } else {
                        viewingButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var editingButtons: some View {
        Button("Cancel") {
            onCancel()
        }
        Button("Save") {
            onSave()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(draftFirstName.trimmed().isEmpty || 
                  draftLastName.trimmed().isEmpty)
    }
    
    @ViewBuilder
    private var viewingButtons: some View {
        // Only show Profile Edit/Delete controls if we are on the Overview tab
        if selectedSection == .overview {
            Button("Edit") {
                onEdit()
            }

            Button("Delete", role: .destructive) {
                showDeleteAlert.wrappedValue = true
            }
        }

        // "Done" is useful for closing the sheet on iPhone/iPad modal
        Button("Done") {
            onDone()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
    }
}

#if os(macOS)
/// The Mac record pane is inline, not a sheet, so it deliberately has no
/// standing bottom bar — a permanent "Done" button would be meaningless there.
/// Edit mode still needs somewhere to commit or back out, though: without this
/// bar the profile editor opens with no way to save a change (level included)
/// or to leave the drafts behind.
struct StudentEditActionBar: View {
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
#endif
