import SwiftUI

/// The Procedures sidebar row's page: the Resources screen showing Procedures.
/// (Procedures live in Resources now; the row stays until the sidebar is regrouped.)
struct ProceduresListView: View {
    var body: some View {
        ResourcesView(kind: .procedures)
    }
}
