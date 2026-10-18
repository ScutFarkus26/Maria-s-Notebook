import SwiftUI

/// The Stories sidebar row's page: the Resources screen showing Stories.
/// (Stories live in Resources now; the row stays until the sidebar is regrouped.)
struct StoriesRootView: View {
    var body: some View {
        ResourcesView(kind: .stories)
    }
}
