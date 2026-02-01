import SwiftUI
import SwiftData

/// Detail view for viewing a procedure
struct ProcedureDetailView: View {
    let procedure: Procedure
    var onEdit: ((Procedure) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    private var relatedProcedures: [Procedure] {
        ProcedureService.fetchRelatedProcedures(for: procedure, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with category and metadata
                    headerSection

                    Divider()

                    // Main content
                    contentSection

                    // Related procedures
                    if !relatedProcedures.isEmpty {
                        Divider()
                        relatedProceduresSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 900)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sheetBackground)
            .navigationTitle(procedure.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            onEdit?(procedure)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Delete Procedure",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    ProcedureService.deleteProcedure(procedure, in: modelContext)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(procedure.title)\"? This action cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 550, idealWidth: 700, maxWidth: 900)
        .frame(minHeight: 500, idealHeight: 700, maxHeight: .infinity)
        #endif
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category badge and icon
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(systemName: procedure.displayIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(procedure.category.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !procedure.summary.isEmpty {
                        Text(procedure.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()
            }

            // Metadata
            HStack(spacing: 16) {
                metadataItem(icon: "calendar", label: "Created", value: procedure.createdAt.formatted(date: .abbreviated, time: .omitted))
                metadataItem(icon: "clock.arrow.circlepath", label: "Updated", value: procedure.modifiedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private func metadataItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if procedure.content.isEmpty {
                Text("No content yet. Tap Edit to add procedure details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.vertical, 20)
            } else {
                markdownContent
            }
        }
    }

    @ViewBuilder
    private var markdownContent: some View {
        if let attributedString = parseMarkdown(procedure.content) {
            Text(attributedString)
                .font(.system(size: 15, weight: .regular, design: .default))
                .lineSpacing(6)
                .textSelection(.enabled)
        } else {
            // Fallback for plain text
            Text(procedure.content)
                .font(.system(size: 15, weight: .regular, design: .default))
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }

    // MARK: - Related Procedures Section

    @ViewBuilder
    private var relatedProceduresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Procedures")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(relatedProcedures) { related in
                    HStack(spacing: 10) {
                        Image(systemName: related.displayIcon)
                            .foregroundStyle(.accent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(related.title)
                                .font(.subheadline.weight(.medium))

                            Text(related.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private var sheetBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private func parseMarkdown(_ markdown: String) -> AttributedString? {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            // If inline parsing fails, try full markdown
            do {
                return try AttributedString(markdown: markdown)
            } catch {
                return nil
            }
        }
    }
}

#Preview {
    ProcedureDetailView(
        procedure: Procedure(
            title: "Morning Arrival",
            summary: "Steps for welcoming students and starting the day",
            content: """
            ## Overview

            This procedure outlines the steps for welcoming students each morning and establishing a calm start to the day.

            ## Steps

            1. **7:45 AM** - Unlock classroom and prepare materials
            2. **8:00 AM** - Greet students at the door
            3. **8:00-8:15** - Students unpack and choose morning work
            4. **8:15 AM** - Morning circle begins

            ## Materials Needed

            - Attendance clipboard
            - Morning work bins
            - Circle time materials

            ## Notes

            - Allow 2-3 minutes grace period for late arrivals
            - Substitute teachers: see backup folder in desk
            """,
            category: .dailyRoutines,
            icon: "sunrise"
        )
    )
}
