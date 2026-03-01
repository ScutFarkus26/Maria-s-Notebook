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
            tagSelectionSection
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
        .adaptiveAnimation(.easeInOut(duration: UIConstants.AnimationDuration.quick), value: detectedStudentIDs)
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

    // MARK: - Tag Selection Section

    var tagSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Tags")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
                if !bodyText.trimmed().isEmpty {
                    Button {
                        Task { await suggestTagsAndScope() }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xsmall) {
                            Image(systemName: "wand.and.stars")
                            Text(isSuggesting ? "Suggesting…" : "Suggest Tags")
                        }
                    }
                    .disabled(isSuggesting)
                }
#endif
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            TagBadge(tag: tag)
                            Button {
                                adaptiveWithAnimation { tags.removeAll { $0 == tag } }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        showingTagPicker = true
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xsmall) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add Tag")
                                .font(AppTheme.ScaledFont.caption.weight(.medium))
                        }
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.verySmall)
                        .background(Color.secondary.opacity(UIConstants.OpacityConstants.light))
                        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppTheme.Spacing.xxsmall)
            }
            .sheet(isPresented: $showingTagPicker) {
                NoteTagPickerSheet(selectedTags: $tags)
            }
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Toggle(isOn: $needsFollowUp) {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(AppColors.destructive)
                    Text("Follow Up")
                }
            }
            .font(AppTheme.ScaledFont.body)

            Toggle(isOn: $includeInReport) {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                    Text("Include in Report")
                }
            }
            .font(AppTheme.ScaledFont.body)
        }
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
            // Apply template tags, merging with any existing
            for tag in template.tags where !tags.contains(tag) {
                tags.append(tag)
            }
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
    @State private var selectedFilterTag: String?

    /// All unique tags used across templates
    private var allTemplateTags: [String] {
        var tagSet = Set<String>()
        for template in templates {
            for tag in template.tags { tagSet.insert(tag) }
        }
        return tagSet.sorted { TagHelper.tagName($0).localizedCaseInsensitiveCompare(TagHelper.tagName($1)) == .orderedAscending }
    }

    var filteredTemplates: [NoteTemplate] {
        if let filterTag = selectedFilterTag {
            return templates.filter { $0.tags.contains(filterTag) }
        }
        return templates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Header with expand/collapse
            Button {
                adaptiveWithAnimation(.easeInOut(duration: UIConstants.AnimationDuration.quick)) {
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
                    adaptiveWithAnimation {
                        selectedFilterTag = nil
                    }
                } label: {
                    Text("All")
                        .font(.caption)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, AppTheme.Spacing.xsmall)
                        .background(
                            Capsule()
                                .fill(selectedFilterTag == nil ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                        )
                        .foregroundStyle(selectedFilterTag == nil ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                // Tag filter chips
                ForEach(allTemplateTags, id: \.self) { tag in
                    let count = templates.filter { $0.tags.contains(tag) }.count
                    if count > 0 {
                        let tagColor = TagHelper.tagColor(tag).color
                        Button {
                            adaptiveWithAnimation {
                                selectedFilterTag = (selectedFilterTag == tag) ? nil : tag
                            }
                        } label: {
                            Text(TagHelper.tagName(tag))
                                .font(.caption)
                                .padding(.horizontal, AppTheme.Spacing.small)
                                .padding(.vertical, AppTheme.Spacing.xsmall)
                                .background(
                                    Capsule()
                                        .fill(selectedFilterTag == tag ? tagColor.opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                                )
                                .foregroundStyle(selectedFilterTag == tag ? tagColor : .secondary)
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
                let chipColor = template.tags.first.map { TagHelper.tagColor($0).color } ?? Color.gray
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
                                .fill(chipColor.opacity(UIConstants.OpacityConstants.light))
                        )
                        .foregroundStyle(chipColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(template.title)
                .accessibilityHint("Double tap to insert: \(template.body)")
            }
        }
    }
}

// Note: Uses FlowLayout from /Components/FlowLayout.swift
