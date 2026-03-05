import SwiftUI

/// Sheet for selecting import options
struct AttachmentImportOptionsSheet: View {
    let lesson: Lesson
    @Binding var selectedScope: AttachmentScope
    @Binding var deleteOriginal: Bool
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)

                Text("Import Options")
                    .font(AppTheme.ScaledFont.titleMedium)
            }
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 16) {
                // Scope selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachment Scope")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ScopeOptionButton(
                            scope: .lesson,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )

                        ScopeOptionButton(
                            scope: .group,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )

                        ScopeOptionButton(
                            scope: .subject,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )
                    }
                }

                Divider()

                // Delete original option
                Toggle(isOn: $deleteOriginal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Move original to trash")
                            .font(AppTheme.ScaledFont.captionSemibold)
                        Text("Delete the original file after importing")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
            }
            .padding(.horizontal, 20)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    onImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
    }
}

/// Button for selecting attachment scope
struct ScopeOptionButton: View {
    let scope: AttachmentScope
    @Binding var selectedScope: AttachmentScope
    let lesson: Lesson

    private var isSelected: Bool {
        selectedScope == scope
    }

    private var subtitle: String {
        switch scope {
        case .lesson:
            return "Only visible in this lesson"
        case .group:
            return "Visible in all lessons in \"\(lesson.group)\""
        case .subject:
            return "Visible in all lessons in \"\(lesson.subject)\""
        }
    }

    var body: some View {
        Button(action: { selectedScope = scope }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.displayName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
