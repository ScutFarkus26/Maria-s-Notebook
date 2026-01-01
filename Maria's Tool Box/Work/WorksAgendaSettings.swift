import SwiftUI

public enum WorksAgendaPrefs {
    public static let showTabKey = "WorksAgenda.showTab"
}

public struct WorksAgendaSettingsView: View {
    @AppStorage(WorksAgendaPrefs.showTabKey) private var showWorksAgenda: Bool = true

    public init() {}

    public var body: some View {
        Form {
            Section("Works Agenda") {
                Toggle("Show Works Agenda tab", isOn: $showWorksAgenda)
            }
        }
    }
}

#Preview {
    WorksAgendaSettingsView()
}
