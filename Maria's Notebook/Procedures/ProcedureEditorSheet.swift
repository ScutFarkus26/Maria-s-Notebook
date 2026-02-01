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

    private var isEditing: Bool { procedure != nil }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(procedure: Procedure?) {
        self.procedure = procedure
        if let procedure = procedure {
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
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text(isEditing ? "Edit Procedure" : "New Procedure")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    // Basic Info Section
                    basicInfoSection

                    Divider()

                    // Category Section
                    categorySection

                    Divider()

                    // Content Section
                    contentSection

                    // Help text
                    helpText
                }
                .padding(24)
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
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 550, minHeight: 600)
        #endif
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(selectedIcon: $icon)
        }
    }

    // MARK: - Basic Info Section

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Information")
                .font(.headline)

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., Morning Arrival", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Summary
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Brief description for list view", text: $summary)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Current icon preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProcedureCategory.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.caption)
                                Text(cat.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(category == cat ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                            .foregroundStyle(category == cat ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content")
                .font(.headline)

            Text("Use Markdown formatting for headings, lists, and emphasis.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $content)
                .font(.system(size: 14, design: .monospaced))
                .frame(minHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                )
        }
    }

    // MARK: - Help Text

    @ViewBuilder
    private var helpText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markdown Tips")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                markdownTip("## Heading", "Creates a section heading")
                markdownTip("**bold**", "Makes text bold")
                markdownTip("- item", "Creates a bullet list")
                markdownTip("1. item", "Creates a numbered list")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func markdownTip(_ syntax: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(syntax)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.accent)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let procedure = procedure {
            // Update existing
            ProcedureService.updateProcedure(
                procedure,
                title: trimmedTitle,
                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                category: category,
                icon: icon,
                relatedProcedureIDs: procedure.relatedProcedureIDs,
                in: modelContext
            )
        } else {
            // Create new
            _ = ProcedureService.createProcedure(
                title: trimmedTitle,
                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
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
                    GridItem(.adaptive(minimum: 60), spacing: 12)
                ], spacing: 12) {
                    ForEach(procedureIcons, id: \.self) { iconName in
                        Button {
                            selectedIcon = iconName
                            dismiss()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedIcon == iconName ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                    .frame(width: 60, height: 60)

                                Image(systemName: iconName)
                                    .font(.system(size: 24))
                                    .foregroundStyle(selectedIcon == iconName ? .accent : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
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
        .frame(minWidth: 350, minHeight: 400)
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
