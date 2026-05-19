import SwiftUI
import CoreData

#if os(macOS)
extension TodoEditSheet {
    // MARK: - macOS Layout
    var macOSLayout: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Task")
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    Menu {
                        ShareLink(item: formatTodoForSharing()) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showingSaveAsTemplate = true
                        } label: {
                            Label("Save as Template", systemImage: "doc.badge.plus")
                        }
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
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Section
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
                .padding(28)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 550)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            isTitleFocused = true
        }
        .alert("Save as Template", isPresented: $showingSaveAsTemplate) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {
                templateName = ""
            }
            Button("Save") {
                saveAsTemplate()
            }
        } message: {
            Text("Enter a name for this template")
        }
    }
}
#endif
