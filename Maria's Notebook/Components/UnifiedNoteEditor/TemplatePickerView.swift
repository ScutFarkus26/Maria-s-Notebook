// TemplatePickerView.swift
// Template picker component for the note editor - extracted from NoteEditorSections.swift

import SwiftUI
import SwiftData

// MARK: - Template Picker View

struct TemplatePickerView: View {
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
