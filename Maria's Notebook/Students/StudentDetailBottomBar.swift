// StudentDetailBottomBar.swift
// Bottom bar component extracted from StudentDetailView

import SwiftUI

struct StudentDetailBottomBar: View {
    let isEditing: Bool
    let selectedTab: StudentDetailTab
    let showDeleteAlert: Binding<Bool>
    let draftFirstName: String
    let draftLastName: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void
    
    var body: some View {
        // Hide the bar if we're not editing and not on overview (only "Done" would show, which is redundant on iPad/Mac)
        if isEditing || selectedTab == .overview {
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
        if selectedTab == .overview {
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

