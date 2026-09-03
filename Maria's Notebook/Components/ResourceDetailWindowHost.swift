import CoreData
import SwiftUI

#if os(macOS)
struct ResourceDetailWindowHost: View {
    let resourceID: UUID

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if let resource = viewContext.object(CDResource.self, id: resourceID) {
            ResourceDetailView(resource: resource)
                .frame(minWidth: 640, minHeight: 540)
                .navigationTitle(resource.title.isEmpty ? "Resource" : resource.title)
        } else {
            ContentUnavailableView(
                "Resource Not Found",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This resource may have been deleted in another window.")
            )
            .frame(minWidth: 500, minHeight: 360)
        }
    }
}
#endif
