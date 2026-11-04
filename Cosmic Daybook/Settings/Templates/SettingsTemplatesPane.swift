import SwiftUI

// MARK: - Templates Pane

/// Settings › Templates: the meeting template library.
struct SettingsTemplatesPane: View {
    var statsViewModel: SettingsStatsViewModel

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.meetingTemplates) {
                templateLibraryRow(
                    count: statsViewModel.meetingTemplatesCount,
                    title: "Manage meeting templates"
                ) {
                    MeetingTemplateManagementView()
                        .settingsBreadcrumb("Settings › Templates")
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func templateLibraryRow<Destination: View>(
        count: Int,
        title: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        #if os(macOS)
        HStack {
            Text(Self.countText(count))
                .foregroundStyle(.secondary)
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
            SettingsLinkRow(title: title, systemImage: "doc.on.doc", detail: Self.countText(count))
        }
        .buttonStyle(.plain)
        #endif
    }

    private static func countText(_ count: Int) -> String {
        count == 1 ? "1 template" : "\(count) templates"
    }
}
