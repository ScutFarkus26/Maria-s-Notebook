import SwiftUI

/// Settings screen for lead guides to configure what assistants can write.
/// Only visible when the current user is a lead guide.
struct AssistantPermissionsView: View {
    @State private var enabledCategories: Set<SharingPermissionCategory>

    init() {
        _enabledCategories = State(initialValue: SharingPreferences.assistantWritableCategories())
    }

    var body: some View {
        List {
            Section {
                Text("Control which types of data your assistants can create and edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Assistant Write Access") {
                ForEach(SharingPermissionCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label(category.displayName, systemImage: category.icon)
                    }
                }
            }

            Section {
                Text("Assistants can always view all shared classroom data. These settings only control write access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Assistant Permissions")
    }

    private func binding(for category: SharingPermissionCategory) -> Binding<Bool> {
        Binding(
            get: { enabledCategories.contains(category) },
            set: { enabled in
                if enabled {
                    enabledCategories.insert(category)
                } else {
                    enabledCategories.remove(category)
                }
                SharingPreferences.setAssistantWritableCategories(enabledCategories)
            }
        )
    }
}
