// TemplateEditorSheet.swift
// The shared create/edit sheet behind the meeting- and note-template editors.
// The chrome (navigation title, Cancel/Save toolbar, save + dismiss, platform
// presentation) is identical; each editor supplies a `TemplateEditing` adapter
// for its draft, its form sections and its Core Data writes.

import SwiftUI
import CoreData
import OSLog

// MARK: - Adapter

protocol TemplateEditing {
    associatedtype Template: NSManagedObject
    /// The editable copy of a template's fields, held in `@State` by the sheet.
    associatedtype Draft
    associatedtype Fields: View

    /// Minimum window size for the sheet on macOS.
    static var macOSMinSize: CGSize { get }
    /// How scrolling the form dismisses the keyboard on iOS.
    static var keyboardDismissMode: ScrollDismissesKeyboardMode { get }

    static func makeDraft(from template: Template?) -> Draft
    static func canSave(_ draft: Draft) -> Bool
    @ViewBuilder static func fields(_ draft: Binding<Draft>) -> Fields
    static func apply(_ draft: Draft, to template: Template)
    static func insert(_ draft: Draft, sortOrder: Int64, into context: NSManagedObjectContext)
}

extension TemplateEditing {
    static var keyboardDismissMode: ScrollDismissesKeyboardMode { .automatic }
}

// MARK: - Sheet

struct TemplateEditorSheet<Adapter: TemplateEditing>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let template: Adapter.Template?
    var onSaved: () -> Void

    @State private var draft: Adapter.Draft
    @State private var saveTrigger = 0

    private var isEditing: Bool { template != nil }

    init(template: Adapter.Template?, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        _draft = State(initialValue: Adapter.makeDraft(from: template))
    }

    var body: some View {
        NavigationStack {
            Form {
                Adapter.fields($draft)
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .inlineNavigationTitle()
            #if os(iOS)
            .scrollDismissesKeyboard(Adapter.keyboardDismissMode)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!Adapter.canSave(draft))
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: Adapter.macOSMinSize.width, minHeight: Adapter.macOSMinSize.height)
        #endif
    }

    // MARK: - Helpers

    private func save() {
        if let existing = template {
            Adapter.apply(draft, to: existing)
        } else {
            let sortOrder = nextCustomTemplateSortOrder(for: Adapter.Template.self, in: viewContext)
            Adapter.insert(draft, sortOrder: sortOrder, into: viewContext)
        }

        if viewContext.safeSave() {
            saveTrigger &+= 1
        }
        onSaved()
        dismiss()
    }
}

/// Sort order for a newly created template: custom templates start at 100 and
/// follow the ones already there.
private func nextCustomTemplateSortOrder<T: NSManagedObject>(
    for type: T.Type,
    in context: NSManagedObjectContext
) -> Int64 {
    let customCount: Int
    do {
        let countRequest = CDFetchRequest(type)
        countRequest.predicate = NSPredicate(format: "isBuiltIn == NO")
        customCount = try context.count(for: countRequest)
    } catch {
        Logger.settings.warning("Failed to fetch custom template count: \(error, privacy: .public)")
        customCount = 0
    }
    return Int64(100 + customCount)
}
