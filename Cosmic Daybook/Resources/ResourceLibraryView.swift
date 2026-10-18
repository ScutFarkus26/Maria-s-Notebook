import SwiftUI

/// The Resources sidebar row's page: the Resources screen, opening on Files.
struct ResourceLibraryView: View {
    var body: some View {
        ResourcesView(kind: .files)
    }
}
