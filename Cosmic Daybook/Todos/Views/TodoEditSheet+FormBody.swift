import SwiftUI
import CoreData

// MARK: - Shared Form Body

extension TodoEditSheet {
    /// The scrolling form both platforms present. Only the chrome around it
    /// differs — iOS wraps it in a `NavigationStack` with toolbar items, macOS
    /// in a custom header row — so the sections themselves live here once.
    /// `contentPadding` is the inset each platform's layout uses (iOS 20,
    /// macOS 28).
    func formBody(contentPadding: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title Section
                titleSection

                Divider()

                // Students Section
                studentSection

                Divider()

                // Due Date Section
                dueDateSection

                Divider()

                // Priority Section
                prioritySection

                Divider()

                // Recurrence Section
                recurrenceSection

                Divider()

                // Subtasks Section
                subtasksSection

                Divider()

                // Work Integration Section
                workIntegrationSection

                Divider()

                // Attachments Section
                attachmentsSection

                Divider()

                // Time Estimate Section
                timeEstimateSection

                Divider()

                // CDReminder Section
                reminderSection

                Divider()

                // Mood & Reflection Section
                moodReflectionSection

                Divider()

                // Location CDReminder Section
                locationReminderSection

                Divider()

                // Notes Section
                notesSection
            }
            .padding(contentPadding)
        }
    }

    // MARK: - Title & Notes

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Title")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .font(AppTheme.ScaledFont.callout)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextEditor(text: $notes)
                .font(AppTheme.ScaledFont.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                .cornerRadius(8)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Overflow Menu

    /// The share / "Save as Template" items both platforms put behind the
    /// ellipsis menu. Only the menu's label differs between them.
    @ViewBuilder
    var shareAndTemplateMenuItems: some View {
        ShareLink(item: formatTodoForSharing()) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            showingSaveAsTemplate = true
        } label: {
            Label("Save as Template", systemImage: "doc.badge.plus")
        }
    }
}

// MARK: - Save as Template Alert

/// The "Save as Template" prompt both platform layouts attach to their root.
struct TodoSaveAsTemplateAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var templateName: String
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Save as Template", isPresented: $isPresented) {
                TextField("Template name", text: $templateName)
                Button("Cancel", role: .cancel) {
                    templateName = ""
                }
                Button("Save") {
                    onSave()
                }
            } message: {
                Text("Enter a name for this template")
            }
    }
}
