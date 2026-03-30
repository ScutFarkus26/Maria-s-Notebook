import SwiftUI
import SwiftData

#if !os(macOS)
extension TodoEditSheet {
    // MARK: - iOS Layout
    var iOSLayout: some View {
        NavigationStack {
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

                    // Reminder Section
                    reminderSection

                    Divider()

                    // Mood & Reflection Section
                    moodReflectionSection

                    Divider()

                    // Location Reminder Section
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
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                            .scrollContentBackground(.hidden)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Edit Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeEditor() }
                }
                ToolbarItem(placement: .primaryAction) {
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
