import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Sheet for selecting import options and picking a file
struct AttachmentImportOptionsSheet: View {
    let lesson: CDLesson
    @Binding var selectedScope: AttachmentScope
    @Binding var deleteOriginal: Bool
    let onFileSelected: (Result<[URL], Error>) -> Void
    let onCancel: () -> Void

    @State private var showingImporter = false

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
                    showingImporter = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, UTType(filenameExtension: "pages") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            onFileSelected(result)
        }
    }
}

/// Button for selecting attachment scope
struct ScopeOptionButton: View {
    let scope: AttachmentScope
    @Binding var selectedScope: AttachmentScope
    let lesson: CDLesson

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
        Button(action: { selectedScope = scope }, label: {
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
                    .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 1.5)
            )
        })
        .buttonStyle(.plain)
    }
}
