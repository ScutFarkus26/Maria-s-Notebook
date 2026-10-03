import CoreData
import SwiftUI

#if os(macOS)
struct ResourceDetailWindowHost: View {
    let resourceID: UUID

    var body: some View {
        EntityWindowHost(
            id: resourceID,
            minSize: CGSize(width: 640, height: 540),
            notFound: WindowHostNotFound(
                "Resource Not Found",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This resource may have been deleted in another window."),
                minSize: CGSize(width: 500, height: 360)
            )
        ) { (resource: CDResource) in
            ResourceDetailView(resource: resource)
                .navigationTitle(resource.title.isEmpty ? "Resource" : resource.title)
        }
    }
}
#endif
