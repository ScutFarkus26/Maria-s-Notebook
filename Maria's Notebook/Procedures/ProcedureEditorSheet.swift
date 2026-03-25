import SwiftUI
import SwiftData

/// Sheet for adding or editing a procedure
struct ProcedureEditorSheet: View {
    let procedure: Procedure?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var content: String = ""
    @State private var category: ProcedureCategory = .dailyRoutines
    @State private var icon: String = ""
    @State private var showingIconPicker = false
    @State private var aiTriggerCounter: Int = 0

    private var isEditing: Bool { procedure != nil }

    private var isValid: Bool {
        !title.trimmed().isEmpty
    }

    init(procedure: Procedure?) {
        self.procedure = procedure
        if let procedure {
            _title = State(initialValue: procedure.title)
            _summary = State(initialValue: procedure.summary)
            _content = State(initialValue: procedure.content)
            _category = State(initialValue: procedure.category)
            _icon = State(initialValue: procedure.icon)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    // Header
                    Text(isEditing ? "Edit Procedure" : "New Procedure")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    // Basic Info Section
                    basicInfoSection

                    Divider()

                    // Category Section
                    categorySection

                    Divider()

                    // Content Section
                    contentSection
                }
                .padding(AppTheme.Spacing.large)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isEditing ? "Save Changes" : "Add Procedure") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(AppTheme.Spacing.medium)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: UIConstants.SheetSize.medium.width, minHeight: UIConstants.SheetSize.medium.height)
        #endif
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(selectedIcon: $icon)
        }
    }

    // MARK: - Basic Info Section

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Basic Information")
                .font(.headline)

            // Title
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., Morning Arrival", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Summary
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Brief description for list view", text: $summary)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Icon (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: AppTheme.Spacing.compact) {
                    // Current icon preview
                    ZStack {
                        let avatarHalf = UIConstants.CardSize.studentAvatar / 2
                        RoundedRectangle(
                            cornerRadius: UIConstants.CornerRadius.medium,
                            style: .continuous
                        )
                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                        .frame(width: avatarHalf, height: avatarHalf)

                        Image(systemName: icon.isEmpty ? category.icon : icon)
                            .font(.system(size: 20))
                            .foregroundStyle(.accent)
                    }

                    Button {
                        showingIconPicker = true
                    } label: {
                        Text(icon.isEmpty ? "Choose Icon" : "Change Icon")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !icon.isEmpty {
                        Button {
                            icon = ""
                        } label: {
                            Text("Use Default")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Category Section

    @ViewBuilder
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Category")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(ProcedureCategory.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            HStack(spacing: AppTheme.Spacing.verySmall) {
                                Image(systemName: cat.icon)
                                    .font(.caption)
                                Text(cat.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(
                                category == cat
                                    ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                                    : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                            )
                            .foregroundStyle(category == cat ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxsmall)
            }

            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Content")
                .font(.headline)

            ZStack(alignment: .bottomTrailing) {
                SmartTextEditor(text: $content, triggerTool: $aiTriggerCounter)
                    .frame(minHeight: AppTheme.Spacing.xlarge * 3)
                    .padding(AppTheme.Spacing.small)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.faint))
                    )

                if #available(iOS 18.0, macOS 15.0, *) {
                    Button {
                        aiTriggerCounter += 1
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(
                                size: UIConstants.CardSize.iconSize,
                                weight: .semibold
                            ))
                            .foregroundStyle(.white)
                            .frame(
                                width: UIConstants.CardSize.iconSizeLarge + 8,
                                height: UIConstants.CardSize.iconSizeLarge + 8
                            )
                            .background(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(
                                color: .black.opacity(UIConstants.OpacityConstants.accent),
                                radius: AppTheme.Spacing.compact,
                                y: AppTheme.Spacing.xxsmall
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }

        if let procedure {
            // Update existing
            ProcedureService.updateProcedure(
                procedure,
                title: trimmedTitle,
                summary: summary.trimmed(),
                content: content,
                category: category,
                icon: icon,
                relatedProcedureIDs: procedure.relatedProcedureIDs,
                in: modelContext
            )
        } else {
            // Create new
            ProcedureService.createProcedure(
                title: trimmedTitle,
                summary: summary.trimmed(),
                content: content,
                category: category,
                icon: icon,
                relatedProcedureIDs: [],
                in: modelContext
            )
        }

        dismiss()
    }
}

// MARK: - Icon Picker Sheet

struct IconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let procedureIcons: [String] = [
        // Daily Routines
        "sunrise", "sun.max", "sunset", "moon", "clock",
        // Safety
        "flame", "exclamationmark.shield", "cross.case", "bell", "door.left.hand.open",
        // Schedules
        "calendar", "calendar.badge.clock", "clock.arrow.circlepath", "hourglass",
        // Transitions
        "arrow.left.arrow.right", "figure.walk", "arrow.triangle.turn.up.right.diamond",
        // Materials
        "tray.2", "archivebox", "shippingbox", "pencil.and.ruler", "paintbrush",
        // Communication
        "message", "envelope", "phone", "megaphone", "speaker.wave.2",
        // Behavioral
        "hand.raised", "heart", "star", "person.2", "bubble.left.and.bubble.right",
        // General
        "doc.text", "list.bullet", "checklist", "note.text", "bookmark"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 60), spacing: AppTheme.Spacing.compact)
                ], spacing: AppTheme.Spacing.compact) {
                    ForEach(procedureIcons, id: \.self) { iconName in
                        Button {
                            selectedIcon = iconName
                            dismiss()
                        } label: {
                            ZStack {
                                let avatarSize = UIConstants.CardSize.studentAvatar * 0.75
                                RoundedRectangle(
                                    cornerRadius: UIConstants.CornerRadius.large,
                                    style: .continuous
                                )
                                .fill(
                                    selectedIcon == iconName
                                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent + 0.05)
                                        : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                                )
                                .frame(width: avatarSize, height: avatarSize)

                                Image(systemName: iconName)
                                    .font(.system(size: UIConstants.CardSize.iconSizeLarge))
                                    .foregroundStyle(selectedIcon == iconName ? .accent : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppTheme.Spacing.large)
            }
            .navigationTitle("Choose Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: UIConstants.SheetSize.compact.width - 50, minHeight: UIConstants.SheetSize.compact.height)
        #endif
    }
}

#Preview("New Procedure") {
    ProcedureEditorSheet(procedure: nil)
        .previewEnvironment()
}

#Preview("Edit Procedure") {
    ProcedureEditorSheet(
        procedure: Procedure(
            title: "Morning Arrival",
            summary: "Steps for welcoming students",
            content: "## Overview\n\nThis procedure outlines...",
            category: .dailyRoutines,
            icon: "sunrise"
        )
    )
    .previewEnvironment()
}
