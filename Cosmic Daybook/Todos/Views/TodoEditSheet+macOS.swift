import SwiftUI
import CoreData

#if os(macOS)
extension TodoEditSheet {
    // MARK: - macOS Layout
    var macOSLayout: some View {
        VStack(spacing: 0) {
            header

            Divider()

            formBody(contentPadding: 28)
                .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 550)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            isTitleFocused = true
        }
        .modifier(
            TodoSaveAsTemplateAlert(
                isPresented: $showingSaveAsTemplate,
                templateName: $templateName,
                onSave: { saveAsTemplate() }
            )
        )
    }

    /// The window-style header bar that stands in for iOS's navigation bar.
    private var header: some View {
        HStack {
            Text("Edit Task")
                .font(AppTheme.ScaledFont.header)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 12) {
                Menu {
                    shareAndTemplateMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button("Cancel") { closeEditor() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.controlBackgroundColor())
    }
}
#endif
