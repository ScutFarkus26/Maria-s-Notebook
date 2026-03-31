// NoteEditorSections.swift
// View sections for UnifiedNoteEditor - extracted for maintainability
// CDStudent selection UI moved to NoteEditorStudentSelection.swift
// TemplatePickerView moved to TemplatePickerView.swift

import SwiftUI
import CoreData
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
                    .stroke(
                        Color.primary.opacity(UIConstants.OpacityConstants.subtle),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
            )
            .shadow(
                color: Color.black.opacity(UIConstants.OpacityConstants.veryFaint),
                radius: AppTheme.Spacing.verySmall, x: 0, y: AppTheme.Spacing.xsmall
            )
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

    // MARK: - CDNote Body Section

    var noteBodySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("CDNote")
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
                        .stroke(
                            Color.secondary.opacity(UIConstants.OpacityConstants.light),
                            lineWidth: UIConstants.StrokeWidth.thin
                        )
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
                        .stroke(
                            Color.secondary.opacity(UIConstants.OpacityConstants.light),
                            lineWidth: UIConstants.StrokeWidth.thin
                        )
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
                        .stroke(
                            Color.secondary.opacity(UIConstants.OpacityConstants.light),
                            lineWidth: UIConstants.StrokeWidth.thin
                        )
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
                        .stroke(
                            Color.secondary.opacity(UIConstants.OpacityConstants.light),
                            lineWidth: UIConstants.StrokeWidth.thin
                        )
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
                    .frame(
                        width: UIConstants.CardSize.studentAvatar * 0.75,
                        height: UIConstants.CardSize.studentAvatar * 0.75
                    )
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous))
            }
            #else
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: UIConstants.CardSize.studentAvatar * 0.75,
                        height: UIConstants.CardSize.studentAvatar * 0.75
                    )
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

    private func insertTemplate(_ template: CDNoteTemplate) {
        // If body is empty, replace entirely; otherwise append
        if bodyText.trimmed().isEmpty {
            bodyText = template.body
            // Apply template tags, merging with any existing
            for tag in template.tagsArray where !tags.contains(tag) {
                tags.append(tag)
            }
        } else {
            // Append template text with a space separator
            bodyText = bodyText.trimmed() + " " + template.body
        }
    }
}
