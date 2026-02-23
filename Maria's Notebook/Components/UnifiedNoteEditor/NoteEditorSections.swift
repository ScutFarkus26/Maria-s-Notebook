// NoteEditorSections.swift
// View sections for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - UnifiedNoteEditor Sections Extension

extension UnifiedNoteEditor {

    // MARK: - Main Content Card

    var mainContentCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if shouldShowStudentSelection {
                surfacingBanner
                studentSelectionSection
            }
            templatePickerSection
            if shouldShowCategory {
                categorySelectionSection
            }
            noteBodySection
            reportToggleSection
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge, style: .continuous)
            .fill(cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge, style: .continuous)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: UIConstants.StrokeWidth.thin)
            )
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.veryFaint), radius: AppTheme.Spacing.verySmall, x: 0, y: AppTheme.Spacing.xsmall)
    }

    // MARK: - Surfacing Banner (Detected Names)

    @ViewBuilder
    var surfacingBanner: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Detected Names")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(Array(detectedStudentIDs), id: \.self) { studentID in
                        if let student = students.first(where: { $0.id == studentID }) {
                            let isSelected = selectedStudentIDs.contains(studentID)
                            let studentName = displayName(for: student)
                            Button {
                                if isSelected {
                                    selectedStudentIDs.remove(studentID)
                                } else {
                                    selectedStudentIDs.insert(studentID)
                                }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.xsmall) {
                                    Text(studentName)
                                        .font(AppTheme.ScaledFont.caption.weight(.medium))
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.scaledRounded(.caption2, weight: .semibold))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                                .padding(.vertical, AppTheme.Spacing.verySmall)
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(studentName)
                            .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxsmall)
            }
        }
        .frame(minHeight: 44)
        .opacity(detectedStudentIDs.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: UIConstants.AnimationDuration.quick), value: detectedStudentIDs)
        .accessibilityHidden(detectedStudentIDs.isEmpty)
    }

    // MARK: - Student Selection Section

    var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Selected Students")
                .font(AppTheme.ScaledFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.small) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(Array(selectedStudentIDs), id: \.self) { studentID in
                            if let student = students.first(where: { $0.id == studentID }) {
                                let studentName = displayName(for: student)
                                HStack(spacing: AppTheme.Spacing.xsmall) {
                                    Text(studentName)
                                        .font(AppTheme.ScaledFont.caption.weight(.medium))
                                    Button {
                                        selectedStudentIDs.remove(studentID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.scaledRounded(.caption2, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Remove \(studentName)")
                                }
                                .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                                .padding(.vertical, AppTheme.Spacing.verySmall)
                                .foregroundStyle(.primary)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                                )
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(studentName), selected")
                                .accessibilityHint("Contains remove button")
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xxsmall)
                }

                Button {
                    showingStudentPicker = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.xsmall) {
                        Image(systemName: "plus.circle.fill")
                            .font(.scaledRounded(.footnote, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Add")
                            .font(AppTheme.ScaledFont.caption.weight(.medium))
                    }
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.verySmall)
                    .foregroundStyle(Color.accentColor)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add student")
                .accessibilityHint("Double tap to open student picker")
                .popover(isPresented: $showingStudentPicker, arrowEdge: .top) {
                    studentPickerPopover
                }
            }
        }
    }

    var studentPickerPopover: some View {
        StudentPickerPopover(
            students: students,
            selectedIDs: $selectedStudentIDs,
            onDone: {
                showingStudentPicker = false
            }
        )
        .padding(AppTheme.Spacing.compact)
        .frame(minWidth: 320)
    }

    // MARK: - Category Selection Section

    var categorySelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Category")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
                if !bodyText.trimmed().isEmpty {
                    Button {
                        Task { await suggestCategoryAndScope() }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xsmall) {
                            Image(systemName: "wand.and.stars")
                            Text(isSuggesting ? "Suggesting…" : "Suggest")
                        }
                    }
                    .disabled(isSuggesting)
                }
#endif
            }

            Picker("Category", selection: $category) {
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
            )
        }
    }

    // MARK: - Note Body Section

    var noteBodySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Note")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                aiToolsButton
            }

            SmartTextEditor(text: $bodyText, triggerTool: $aiTriggerCounter)
                .frame(minHeight: 100, idealHeight: 140)
                .padding(.horizontal, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .fill(notesBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
                )

            HStack {
                expandInitialsButton
                Spacer()
            }

            photoPickerSection
        }
    }

    @ViewBuilder
    private var aiToolsButton: some View {
        if !bodyText.isEmpty {
            if #available(iOS 18.0, macOS 15.0, *) {
                Button {
                    aiTriggerCounter += 1
                } label: {
                    HStack(spacing: AppTheme.Spacing.xsmall) {
                        Image(systemName: "sparkles")
                        Text("Writing Tools")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple)
                #if os(iOS)
                .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                .padding(.vertical, AppTheme.Spacing.xsmall)
                .background(Color.purple.opacity(UIConstants.OpacityConstants.light))
                .clipShape(Capsule())
                #endif
            }
        }
    }

    // MARK: - Photo Section

    var photoPickerSection: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            #if os(iOS)
            cameraButton
            #endif
            photoPickerButton
            photoPreview
            Spacer()
        }
    }

    #if os(iOS)
    var cameraButton: some View {
        Button {
            showingCamera = true
        } label: {
            Label("Take Photo", systemImage: "camera.fill")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
                )
        }
    }
    #endif

    var photoPickerButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
                )
        }
    }

    var expandInitialsButton: some View {
        Button {
            expandInitialsInBodyText()
        } label: {
            Label("Expand Initials", systemImage: "textformat.abc")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
                )
        }
    }

    @ViewBuilder
    var photoPreview: some View {
        if selectedImage != nil {
            photoPreviewContent
        }
    }

    @ViewBuilder
    var photoPreviewContent: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            photoThumbnailView

            Button {
                selectedPhoto = nil
                selectedImage = nil
                imagePath = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var photoThumbnailView: some View {
        Group {
            #if os(macOS)
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIConstants.CardSize.studentAvatar * 0.75, height: UIConstants.CardSize.studentAvatar * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous))
            }
            #else
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIConstants.CardSize.studentAvatar * 0.75, height: UIConstants.CardSize.studentAvatar * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous))
            }
            #endif
        }
    }

    // MARK: - Report Toggle Section

    var reportToggleSection: some View {
        Toggle("Flag for Report", isOn: $includeInReport)
            .font(AppTheme.ScaledFont.body)
            .accessibilityHint(includeInReport ? "Currently flagged. Double tap to unflag." : "Not flagged. Double tap to flag this note for inclusion in reports.")
    }

    // MARK: - Header View (macOS)

    var headerView: some View {
        HStack {
            Text(contextTitle)
                .font(AppTheme.ScaledFont.titleMedium.weight(.bold))
            Spacer()
        }
    }

    // MARK: - Action Buttons (macOS)

    var actionButtons: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                saveNote()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    // MARK: - Template Picker Section

    var templatePickerSection: some View {
        TemplatePickerView { template in
            insertTemplate(template)
        }
    }

    private func insertTemplate(_ template: NoteTemplate) {
        // If body is empty, replace entirely; otherwise append
        if bodyText.trimmed().isEmpty {
            bodyText = template.body
            category = template.category
        } else {
            // Append template text with a space separator
            bodyText = bodyText.trimmed() + " " + template.body
        }
    }
}

// MARK: - Template Picker View

private struct TemplatePickerView: View {
    @Query(sort: [
        SortDescriptor(\NoteTemplate.sortOrder),
        SortDescriptor(\NoteTemplate.title)
    ]) var templates: [NoteTemplate]

    let onSelect: (NoteTemplate) -> Void

    @State private var isExpanded: Bool = false
    @State private var selectedCategory: NoteCategory? = nil

    var filteredTemplates: [NoteTemplate] {
        if let cat = selectedCategory {
            return templates.filter { $0.category == cat }
        }
        return templates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Header with expand/collapse
            Button {
                withAnimation(.easeInOut(duration: UIConstants.AnimationDuration.quick)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Quick Insert")
                        .font(AppTheme.ScaledFont.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand template options")

            if isExpanded {
                // Category filter
                categoryFilterRow

                // Template chips
                if filteredTemplates.isEmpty {
                    Text("No templates available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, AppTheme.Spacing.xsmall)
                } else {
                    templateChipsGrid
                }
            }
        }
    }

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                // "All" chip
                Button {
                    withAnimation {
                        selectedCategory = nil
                    }
                } label: {
                    Text("All")
                        .font(.caption)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, AppTheme.Spacing.xsmall)
                        .background(
                            Capsule()
                                .fill(selectedCategory == nil ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                        )
                        .foregroundStyle(selectedCategory == nil ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                // Category chips
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    let count = templates.filter { $0.category == cat }.count
                    if count > 0 {
                        Button {
                            withAnimation {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        } label: {
                            Text(cat.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, AppTheme.Spacing.small)
                                .padding(.vertical, AppTheme.Spacing.xsmall)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == cat ? categoryColor(cat).opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                                )
                                .foregroundStyle(selectedCategory == cat ? categoryColor(cat) : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var templateChipsGrid: some View {
        FlowLayout(spacing: AppTheme.Spacing.verySmall) {
            ForEach(filteredTemplates) { template in
                Button {
                    onSelect(template)
                } label: {
                    Text(template.title)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                        .padding(.vertical, AppTheme.Spacing.verySmall)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge, style: .continuous)
                                .fill(categoryColor(template.category).opacity(UIConstants.OpacityConstants.light))
                        )
                        .foregroundStyle(categoryColor(template.category))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(template.title)
                .accessibilityHint("Double tap to insert: \(template.body)")
            }
        }
    }

    private func categoryColor(_ category: NoteCategory) -> Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .green
        case .general: return .gray
        }
    }
}

// Note: Uses FlowLayout from /Components/FlowLayout.swift
