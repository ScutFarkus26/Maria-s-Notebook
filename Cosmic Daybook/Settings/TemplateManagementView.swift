// TemplateManagementView.swift
// The shared "manage templates" settings screen. Meeting templates and note
// templates render the same list, card rows, empty state and toolbar; each one
// supplies a `TemplateManaging` adapter for the parts that differ.

import SwiftUI
import CoreData

// MARK: - Adapter

/// Everything the shared template-management screen needs to know about one
/// kind of template. Conformers are caseless enums, one per entity.
protocol TemplateManaging {
    associatedtype Template: NSManagedObject & Identifiable
    associatedtype EditorSheet: View
    associatedtype PreviewSheet: View

    /// Sort order for the screen's `@FetchRequest`.
    static var sortDescriptors: [NSSortDescriptor] { get }
    static var navigationTitle: String { get }
    /// Caption below the built-in section.
    static var builtInFooter: String { get }
    /// Caption below the custom section.
    static var customFooter: String { get }
    /// `true` when exactly one template can be marked active.
    static var supportsActivation: Bool { get }
    /// Lines of the card row's subtitle.
    static var subtitleLineLimit: Int { get }

    static func isBuiltIn(_ template: Template) -> Bool
    static func isActive(_ template: Template) -> Bool
    static func title(of template: Template) -> String
    static func subtitle(of template: Template) -> String
    /// Tag badges beside the row title (the first two are shown).
    static func tags(of template: Template) -> [String]

    static func seedIfNeeded(in context: NSManagedObjectContext)
    static func activate(_ template: Template, in context: NSManagedObjectContext)
    static func delete(_ template: Template, in context: NSManagedObjectContext)

    @ViewBuilder static func editorSheet(for template: Template?) -> EditorSheet
    @ViewBuilder static func previewSheet(
        for template: Template,
        onActivate: @escaping () -> Void
    ) -> PreviewSheet
}

extension TemplateManaging {
    static var supportsActivation: Bool { false }
    static var subtitleLineLimit: Int { 1 }
    static func isActive(_ template: Template) -> Bool { false }
    static func tags(of template: Template) -> [String] { [] }
    static func seedIfNeeded(in context: NSManagedObjectContext) {}
    static func activate(_ template: Template, in context: NSManagedObjectContext) {}
}

// MARK: - Screen

struct TemplateManagementView<Adapter: TemplateManaging>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var templates: FetchedResults<Adapter.Template>

    @State private var showingAddSheet = false
    @State private var editingTemplate: Adapter.Template?
    @State private var previewingTemplate: Adapter.Template?

    init() {
        _templates = FetchRequest(sortDescriptors: Adapter.sortDescriptors)
    }

    private var builtInTemplates: [Adapter.Template] {
        templates.filter { Adapter.isBuiltIn($0) }
    }

    private var customTemplates: [Adapter.Template] {
        templates.filter { !Adapter.isBuiltIn($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
                builtInSection
                customSection
            }
            .padding(SettingsStyle.padding)
        }
        .navigationTitle(Adapter.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Template", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            Adapter.editorSheet(for: nil)
        }
        .sheet(item: $editingTemplate) { template in
            Adapter.editorSheet(for: template)
        }
        .sheet(item: $previewingTemplate) { template in
            Adapter.previewSheet(for: template) {
                activateTemplate(template)
            }
        }
        .onAppear {
            Adapter.seedIfNeeded(in: viewContext)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var builtInSection: some View {
        if !builtInTemplates.isEmpty {
            VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                Text("Built-in Templates")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(builtInTemplates) { template in
                    cardRow(for: template, isBuiltIn: true)
                }

                Text(Adapter.builtInFooter)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            Text("My Templates")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            if customTemplates.isEmpty {
                emptyState
            } else {
                ForEach(customTemplates) { template in
                    cardRow(for: template, isBuiltIn: false)
                }
            }

            Text(Adapter.customFooter)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "doc.badge.plus")
                .foregroundStyle(.secondary)
            Text("No custom templates yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    Color.primary.opacity(UIConstants.OpacityConstants.light),
                    style: StrokeStyle(lineWidth: 1, dash: [5])
                )
        )
    }

    private func cardRow(for template: Adapter.Template, isBuiltIn: Bool) -> TemplateCardRow<Adapter> {
        TemplateCardRow<Adapter>(
            template: template,
            isBuiltIn: isBuiltIn,
            onTap: { previewingTemplate = template },
            onActivate: Adapter.supportsActivation ? { activateTemplate(template) } : nil,
            onEdit: isBuiltIn ? nil : { editingTemplate = template },
            onDelete: isBuiltIn ? nil : { deleteTemplate(template) }
        )
    }

    // MARK: - Actions

    private func activateTemplate(_ template: Adapter.Template) {
        adaptiveWithAnimation {
            Adapter.activate(template, in: viewContext)
        }
    }

    private func deleteTemplate(_ template: Adapter.Template) {
        adaptiveWithAnimation {
            Adapter.delete(template, in: viewContext)
        }
    }
}

// MARK: - Template Card Row

private struct TemplateCardRow<Adapter: TemplateManaging>: View {
    let template: Adapter.Template
    let isBuiltIn: Bool
    let onTap: () -> Void
    let onActivate: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    private var isActive: Bool { Adapter.isActive(template) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Active indicator
                if Adapter.supportsActivation {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(UIConstants.OpacityConstants.semi))
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(Adapter.title(of: template))
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isActive {
                            activeBadge
                        }

                        ForEach(Adapter.tags(of: template).prefix(2), id: \.self) { tag in
                            TagBadge(tag: tag, compact: true)
                        }
                    }

                    Text(Adapter.subtitle(of: template))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(Adapter.subtitleLineLimit)
                }

                Spacer()

                if isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if Adapter.supportsActivation || !isBuiltIn {
                    actionsMenu
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(SettingsStyle.compactPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsStyle.groupBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive
                            ? AppColors.success.opacity(UIConstants.OpacityConstants.semi)
                            : Color.primary.opacity(SettingsStyle.borderOpacity)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(AppColors.success.opacity(UIConstants.OpacityConstants.accent))
            )
            .foregroundStyle(AppColors.success)
    }

    private var actionsMenu: some View {
        Menu {
            if let onActivate, !isActive {
                Button {
                    onActivate()
                } label: {
                    Label("Set as Active", systemImage: "checkmark.circle")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
