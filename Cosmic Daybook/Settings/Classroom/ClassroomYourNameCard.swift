// ClassroomYourNameCard.swift
// Settings › Classroom: the name the lead guide goes by in the classroom's
// shared list of names (`ClassroomNames`), which his assistants' phones show
// ("Marked Out by Danny") in place of "your guide".

import SwiftUI
import CoreData

/// "Your name", for the lead guide. The field starts from his row in the
/// classroom's list, so every one of his devices shows the same name, and
/// saves when he presses Return or leaves the field (not on every keystroke,
/// which would send a change to iCloud per letter).
struct ClassroomYourNameCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @State private var name = ""
    /// What the field last loaded or saved, so leaving it unchanged writes nothing.
    @State private var stored = ""
    /// The name being saved now, if any: changing it and changing it back
    /// before that save ends must still save the second name.
    @State private var saving: String?
    /// The name is saved on this device but not in the list yet: this
    /// account's iCloud record name hasn't come back.
    @State private var isWaiting = false
    /// The last save was taken back: the Apple Account changed during it.
    @State private var wasNotSaved = false
    @FocusState private var isEditing: Bool

    var body: some View {
        SettingsGroup(
            title: SettingsCopy.YourName.title,
            systemImage: SettingsCopy.YourName.systemImage,
            footer: SettingsCopy.YourName.footer
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                field
                if wasNotSaved {
                    Text(SettingsCopy.YourName.notSaved)
                        .font(.footnote)
                        .foregroundStyle(AppColors.warning)
                } else if isWaiting {
                    Text(SettingsCopy.YourName.waiting)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .onChange(of: isEditing) { _, editing in
            if !editing { commit() }
        }
        .onDisappear(perform: commit)
        // A rename on his other Mac or iPad shows here, unless he's typing.
        .onPresentationDataChangeWhenVisible(of: ["ClassroomPerson"], in: viewContext) {
            if !isEditing { load() }
        }
    }

    @ViewBuilder
    private var field: some View {
        #if os(macOS)
        LabeledContent(SettingsCopy.YourName.title) {
            TextField(SettingsCopy.YourName.title, text: $name, prompt: Text(SettingsCopy.YourName.prompt))
                .frame(minWidth: 260)
                .focused($isEditing)
                .onSubmit(commit)
        }
        #else
        TextField(SettingsCopy.YourName.title, text: $name, prompt: Text(SettingsCopy.YourName.prompt))
            .textFieldStyle(.roundedBorder)
            .textContentType(.givenName)
            .submitLabel(.done)
            .focused($isEditing)
            .onSubmit(commit)
        #endif
    }

    private func load() {
        stored = ClassroomNames.myName(role: .leadGuide, in: viewContext)
        name = stored
        isWaiting = ClassroomIdentity.nameWaitingAs != nil
    }

    private func commit() {
        let typed = name.trimmed()
        guard typed != (saving ?? stored) else { return }
        saving = typed
        wasNotSaved = false
        let coordinator = dependencies.saveCoordinator
        let context = viewContext
        Task {
            let saved = await Self.setName(typed, in: context, save: { coordinator.save($0, reason: "Set your name") })
            if saving == typed { saving = nil }
            switch saved {
            case .saved, .waiting:
                stored = typed
                // Not over what was typed while the name was being saved.
                if name.trimmed() == typed { name = typed }
            case .notSaved:
                // Left as typed, so leaving the field again tries again.
                wasNotSaved = name.trimmed() == typed
            case .failed, .overtaken:
                return
            }
            isWaiting = ClassroomIdentity.nameWaitingAs != nil
        }
    }

    /// What `setName` did.
    enum Saved: Equatable {
        /// In the classroom's list, or there was no name there to clear.
        case saved
        /// Kept on this device until iCloud answers; it goes into the list
        /// later (`ClassroomNames.writeWaitingName`).
        case waiting
        /// Not saved: the Apple Account changed while it was saving, so the
        /// name, typed under the last one, was taken back. The card says so.
        case notSaved
        /// The save failed; the save coordinator says so.
        case failed
        /// A newer name overtook this one, and is saved instead.
        case overtaken
    }

    /// Sets the lead guide's own name in the classroom's list and saves, on
    /// `context`, the view context: his row joins the share from the private
    /// store only through `SharedStoreOrphanGuard`, which sees view-context
    /// saves alone. Before his record name is known, or while CloudKit
    /// doesn't answer, the name waits on the device
    /// (`ClassroomNames.setMyName`) and nothing is saved. It used to say
    /// saved when an account change took the name back (2026-10-09 hunt, #5).
    @discardableResult
    static func setName(
        _ typed: String,
        in context: NSManagedObjectContext,
        save: (NSManagedObjectContext) -> Bool
    ) async -> Saved {
        switch await ClassroomNames.setMyName(typed, role: .leadGuide, in: context) {
        case .written: save(context) ? .saved : .failed
        case .nothingToClear: .saved
        case .waiting: .waiting
        case .nothing: .notSaved
        case .overtaken: .overtaken
        }
    }
}
