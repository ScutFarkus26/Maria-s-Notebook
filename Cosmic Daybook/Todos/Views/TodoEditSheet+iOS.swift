import SwiftUI
import CoreData

#if !os(macOS)
extension TodoEditSheet {
    // MARK: - iOS Layout
    var iOSLayout: some View {
        NavigationStack {
            formBody(contentPadding: 20)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Edit Task")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { closeEditor() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            shareAndTemplateMenuItems
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(300))
                    isTitleFocused = true
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(
            TodoSaveAsTemplateAlert(
                isPresented: $showingSaveAsTemplate,
                templateName: $templateName,
                onSave: { saveAsTemplate() }
            )
        )
    }
}
#endif
