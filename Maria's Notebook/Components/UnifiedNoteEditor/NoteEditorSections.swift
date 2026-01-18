// NoteEditorSections.swift
// View sections for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - UnifiedNoteEditor Sections Extension

extension UnifiedNoteEditor {

    // MARK: - Main Content Card

    var mainContentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowStudentSelection {
                surfacingBanner
                studentSelectionSection
            }
            templatePickerSection
            categorySelectionSection
            noteBodySection
            reportToggleSection
        }
        .padding(16)
        .background(cardBackground)
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Surfacing Banner (Detected Names)

    @ViewBuilder
    var surfacingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Names")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                                HStack(spacing: 4) {
                                    Text(studentName)
                                        .font(AppTheme.ScaledFont.caption.weight(.medium))
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.scaledRounded(.caption2, weight: .semibold))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(isSelected ? .accentColor : .primary)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(studentName)
                            .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minHeight: 44)
        .opacity(detectedStudentIDs.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: detectedStudentIDs)
        .accessibilityHidden(detectedStudentIDs.isEmpty)
    }

    // MARK: - Student Selection Section

    var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Students")
                .font(AppTheme.ScaledFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedStudentIDs), id: \.self) { studentID in
                            if let student = students.first(where: { $0.id == studentID }) {
                                let studentName = displayName(for: student)
                                HStack(spacing: 4) {
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(.primary)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(studentName), selected")
                                .accessibilityHint("Contains remove button")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showingStudentPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.scaledRounded(.footnote, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Add")
                            .font(AppTheme.ScaledFont.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(.accentColor)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.15))
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
        .padding(12)
        .frame(minWidth: 320)
    }

    // MARK: - Category Selection Section

    var categorySelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Category")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
                if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await suggestCategoryAndScope() }
                    } label: {
                        HStack(spacing: 4) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Note Body Section

    var noteBodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                // THE "AI TOOLS" BUTTON
                if !bodyText.isEmpty {
                    if #available(iOS 18.0, macOS 15.0, *) {
                        Button {
                            aiTriggerCounter += 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Writing Tools")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                        #if os(iOS)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                        #endif
                    }
                }
            }

            SmartTextEditor(text: $bodyText, triggerTool: $aiTriggerCounter)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(notesBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                expandInitialsButton
                Spacer()
            }

            photoPickerSection
        }
    }

    // MARK: - Photo Section

    var photoPickerSection: some View {
        HStack(spacing: 12) {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    #endif

    var photoPickerButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
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
        HStack(spacing: 8) {
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
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            #else
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyText = template.body
            category = template.category
        } else {
            // Append template text with a space separator
            bodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + template.body
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
        VStack(alignment: .leading, spacing: 8) {
            // Header with expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
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
                        .padding(.vertical, 4)
                } else {
                    templateChipsGrid
                }
            }
        }
    }

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip
                Button {
                    withAnimation {
                        selectedCategory = nil
                    }
                } label: {
                    Text("All")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(selectedCategory == nil ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == cat ? categoryColor(cat).opacity(0.2) : Color.secondary.opacity(0.1))
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
        FlowLayout(spacing: 6) {
            ForEach(filteredTemplates) { template in
                Button {
                    onSelect(template)
                } label: {
                    Text(template.title)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(categoryColor(template.category).opacity(0.12))
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
