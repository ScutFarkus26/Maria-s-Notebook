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
    /// The name is saved on this device but not in the list yet: this
    /// account's iCloud record name hasn't come back.
    @State private var isWaiting = false
    @FocusState private var isEditing: Bool

    var body: some View {
        SettingsGroup(
            title: SettingsCopy.YourName.title,
            systemImage: SettingsCopy.YourName.systemImage,
            footer: SettingsCopy.YourName.footer
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                field
                if isWaiting {
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
        guard typed != stored else { return }
        let coordinator = dependencies.saveCoordinator
        guard Self.setName(typed, in: viewContext, save: { coordinator.save($0, reason: "Set your name") }) else {
            return
        }
        stored = typed
        name = typed
        isWaiting = ClassroomIdentity.nameWaitingAs != nil
    }

    /// Sets the lead guide's own name in the classroom's list and saves, on
    /// `context`, the view context: his row joins the share from the private
    /// store only through `SharedStoreOrphanGuard`, which sees view-context
    /// saves alone. Before his record name is known the name waits on the
    /// device (`ClassroomNames.setMyName`) and nothing is saved. Returns false
    /// when the save failed.
    @discardableResult
    static func setName(
        _ typed: String,
        in context: NSManagedObjectContext,
        save: (NSManagedObjectContext) -> Bool
    ) -> Bool {
        ClassroomNames.setMyName(typed, role: .leadGuide, in: context)
        return save(context)
    }
}
