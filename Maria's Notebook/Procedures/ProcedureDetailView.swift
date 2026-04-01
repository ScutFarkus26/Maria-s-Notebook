import SwiftUI
import CoreData

/// Detail view for viewing a procedure
struct ProcedureDetailView: View {
    let procedure: CDProcedure
    var onEdit: ((CDProcedure) -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    private var relatedProcedures: [CDProcedure] {
        ProcedureService.fetchRelatedProcedures(for: procedure, in: viewContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
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

                    Spacer(minLength: AppTheme.Spacing.xxlarge)
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.top, AppTheme.Spacing.large)
                .padding(.bottom, AppTheme.Spacing.xxlarge)
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
                "Delete CDProcedure",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    ProcedureService.deleteProcedure(procedure, in: viewContext)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(procedure.title)\"? This action cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: UIConstants.SheetSize.medium.width + 30, idealWidth: 700, maxWidth: 900)
        .frame(minHeight: UIConstants.SheetSize.medium.height - 60, idealHeight: 700, maxHeight: .infinity)
        #endif
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            // Category badge and icon
            HStack(spacing: AppTheme.Spacing.compact) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                        .frame(
                            width: UIConstants.CardSize.studentAvatar * 0.7,
                            height: UIConstants.CardSize.studentAvatar * 0.7
                        )

                    Image(systemName: procedure.displayIcon)
                        .font(.system(size: UIConstants.CardSize.iconSizeLarge))
                        .foregroundStyle(.accent)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
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
            HStack(spacing: AppTheme.Spacing.medium) {
                metadataItem(
                    icon: "calendar",
                    label: "Created",
                    value: (procedure.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted)
                )
                metadataItem(
                    icon: "clock.arrow.circlepath",
                    label: "Updated",
                    value: (procedure.modifiedAt ?? Date()).formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
    }

    private func metadataItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if procedure.content.isEmpty {
                Text("No content yet. Tap Edit to add procedure details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.vertical, AppTheme.Spacing.large)
            } else {
                markdownContent
            }
        }
    }

    @ViewBuilder
    private var markdownContent: some View {
        if let attributedString = parseMarkdown(procedure.content) {
            Text(attributedString)
                .font(AppTheme.ScaledFont.body)
                .lineSpacing(AppTheme.Spacing.verySmall)
                .textSelection(.enabled)
        } else {
            // Fallback for plain text
            Text(procedure.content)
                .font(AppTheme.ScaledFont.body)
                .lineSpacing(AppTheme.Spacing.verySmall)
                .textSelection(.enabled)
        }
    }

    // MARK: - Related Procedures Section

    @ViewBuilder
    private var relatedProceduresSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Related Procedures")
                .font(.headline)

            VStack(spacing: AppTheme.Spacing.small) {
                ForEach(relatedProcedures) { related in
                    HStack(spacing: AppTheme.Spacing.small + AppTheme.Spacing.xxsmall) {
                        Image(systemName: related.displayIcon)
                            .foregroundStyle(.accent)
                            .frame(width: UIConstants.CardSize.iconSizeLarge)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
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
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
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
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let procedure = CDProcedure(context: ctx)
    procedure.title = "Morning Arrival"
    procedure.summary = "Steps for welcoming students and starting the day"
    procedure.content = """
        ## Overview

        This procedure outlines the steps for welcoming students each morning \
        and establishing a calm start to the day.

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
        """
    procedure.category = .dailyRoutines
    procedure.icon = "sunrise"

    return ProcedureDetailView(procedure: procedure)
        .previewEnvironment(using: stack)
}
