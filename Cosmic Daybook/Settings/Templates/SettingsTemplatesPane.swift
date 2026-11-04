import SwiftUI

// MARK: - Templates Pane

/// Settings › Templates: the meeting template library.
struct SettingsTemplatesPane: View {
    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.meetingTemplates) {
                templateLibraryRow(title: "Manage meeting templates") {
                    MeetingTemplateManagementView()
                        .settingsBreadcrumb("Settings › Templates")
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func templateLibraryRow<Destination: View>(
        title: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        #if os(macOS)
        HStack {
            Spacer()
            NavigationLink("\(title)…") {
                destination()
            }
            .buttonStyle(.bordered)
        }
        #else
        NavigationLink {
            destination()
        } label: {
            SettingsLinkRow(title: title, systemImage: "doc.on.doc")
        }
        .buttonStyle(.plain)
        #endif
    }
}
