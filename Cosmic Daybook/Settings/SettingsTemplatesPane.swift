import SwiftUI

// MARK: - Templates Pane

/// Settings › Templates: the note, meeting and to-do template libraries.
struct SettingsTemplatesPane: View {
    var statsViewModel: SettingsStatsViewModel

    @State private var isShowingTodoTemplates = false

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.noteTemplates) {
                templateLibraryRow(
                    count: statsViewModel.noteTemplatesCount,
                    title: "Manage note templates"
                ) {
                    NoteTemplateManagementView()
                        .settingsBreadcrumb("Settings › Templates")
                }
            }

            SettingsGroup(.meetingTemplates) {
                templateLibraryRow(
                    count: statsViewModel.meetingTemplatesCount,
                    title: "Manage meeting templates"
                ) {
                    MeetingTemplateManagementView()
                        .settingsBreadcrumb("Settings › Templates")
                }
            }

            SettingsGroup(.todoTemplates) {
                todoTemplatesRow
            }
        }
        // TodoTemplatesView brings its own navigation stack and Done button,
        // so it opens as a sheet here too, as it does from Todos.
        .sheet(isPresented: $isShowingTodoTemplates) {
            TodoTemplatesView()
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

    @ViewBuilder
    private var todoTemplatesRow: some View {
        let count = statsViewModel.todoTemplatesCount
        #if os(macOS)
        HStack {
            Text(Self.countText(count))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Manage to-do templates…") {
                isShowingTodoTemplates = true
            }
            .buttonStyle(.bordered)
        }
        #else
        Button {
            isShowingTodoTemplates = true
        } label: {
            SettingsLinkRow(title: "Manage to-do templates", systemImage: "doc.on.doc", detail: Self.countText(count))
        }
        .buttonStyle(.plain)
        #endif
    }

    private static func countText(_ count: Int) -> String {
        count == 1 ? "1 template" : "\(count) templates"
    }
}
