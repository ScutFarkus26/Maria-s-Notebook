// TemplateEditorSheet.swift
// The shared create/edit sheet behind the meeting- and note-template editors.
// The chrome (navigation title, Cancel/Save toolbar, save + dismiss, the
// discard question, platform presentation) is identical; each editor supplies
// a `TemplateEditing` adapter for its draft, its form sections and its Core
// Data writes.

import SwiftUI
import CoreData
import OSLog

// MARK: - Adapter

protocol TemplateEditing {
    associatedtype Template: NSManagedObject
    /// The editable copy of a template's fields, held in `@State` by the sheet.
    /// Equatable so the sheet knows when there is typed text to lose.
    associatedtype Draft: Equatable
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
    @Environment(SaveCoordinator.self) private var saveCoordinator

    let template: Adapter.Template?

    /// The fields as the sheet opened, to tell whether anything was typed.
    private let initialDraft: Adapter.Draft
    @State private var draft: Adapter.Draft
    @State private var saveTrigger = 0
    @State private var isConfirmingDiscard = false
    @State private var showingSaveFailure = false
    /// Set once the sheet is closing on purpose (saved, or the discard was
    /// confirmed), so the dismissal question stays out of the way: on the
    /// Mac it is asked for a programmatic `dismiss()` too.
    @State private var isClosing = false

    private var isEditing: Bool { template != nil }
    private var hasChanges: Bool { draft != initialDraft }

    /// The management screen's `@FetchRequest` picks up the save, so there
    /// is no callback to refresh it.
    init(template: Adapter.Template?) {
        self.template = template
        let draft = Adapter.makeDraft(from: template)
        initialDraft = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Adapter.fields($draft)
            }
            .navigationTitle(isEditing ? "Edit template" : "New template")
            .inlineNavigationTitle()
            #if os(iOS)
            .scrollDismissesKeyboard(Adapter.keyboardDismissMode)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            isConfirmingDiscard = true
                        } else {
                            isClosing = true
                        }
                    }
                    .confirmationDialog(
                        SettingsCopy.TemplateEditor.discardTitle,
                        isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button(SettingsCopy.TemplateEditor.discard, role: .destructive) { isClosing = true }
                        Button(SettingsCopy.TemplateEditor.keepEditing, role: .cancel) {}
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
            .alert(SettingsCopy.TemplateEditor.saveFailedTitle, isPresented: $showingSaveFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(SettingsCopy.TemplateEditor.saveFailed)
            }
        }
        // A swipe down or a click outside asks before typed text is lost.
        .dismissalConfirmationDialog(
            SettingsCopy.TemplateEditor.discardTitle,
            shouldPresent: hasChanges && !isClosing
        ) {
            Button(SettingsCopy.TemplateEditor.discard, role: .destructive) {}
            Button(SettingsCopy.TemplateEditor.keepEditing, role: .cancel) {}
        }
        // Dismissing from here, after `isClosing` has reached the dialog
        // above, keeps the Mac from asking about a close the guide chose.
        .onChange(of: isClosing) { _, closing in
            if closing { dismiss() }
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

    /// Saves and closes; on a failed save, takes back only this sheet's
    /// change (a second Save would otherwise make the template twice) and
    /// stays open with the typed text.
    private func save() {
        let saved = saveCoordinator.saveEdit(in: viewContext, reason: "Save template") {
            if let existing = template {
                Adapter.apply(draft, to: existing)
            } else {
                let sortOrder = TemplateSortOrder.nextCustom(for: Adapter.Template.self, in: viewContext)
                Adapter.insert(draft, sortOrder: sortOrder, into: viewContext)
            }
        }
        guard saved else {
            showingSaveFailure = true
            return
        }
        saveTrigger &+= 1
        isClosing = true
    }
}

/// Sort order for a newly created template: custom templates start at 100 and
/// each new one goes after the last. "100 + how many there are" gave two the
/// same place once one had been deleted.
enum TemplateSortOrder {
    static let firstCustom: Int64 = 100

    static func nextCustom<T: NSManagedObject>(
        for type: T.Type,
        in context: NSManagedObjectContext
    ) -> Int64 {
        let request = CDFetchRequest(type)
        request.predicate = NSPredicate(format: "isBuiltIn == NO")
        let customs: [T]
        do {
            customs = try context.fetch(request)
        } catch {
            Logger.settings.warning("Failed to fetch custom templates: \(error, privacy: .public)")
            customs = []
        }
        let last = customs.compactMap { ($0.value(forKey: "sortOrder") as? NSNumber)?.int64Value }.max()
        guard let last else { return firstCustom }
        return max(firstCustom, last + 1)
    }
}
