import CoreData
import SwiftUI

#if os(macOS)
struct CommunityTopicWindowHost: View {
    let topicID: UUID

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    var body: some View {
        if let topic = viewContext.object(CDCommunityTopicEntity.self, id: topicID) {
            TopicDetailView(topic: topic) { _ in
                saveCoordinator.save(viewContext, reason: "Update community topic")
            }
            .frame(minWidth: 600, minHeight: 500)
            .navigationTitle(topic.title.isEmpty ? "Community Topic" : topic.title)
        } else {
            ContentUnavailableView(
                "Topic Not Found",
                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                description: Text("This topic may have been deleted in another window.")
            )
            .frame(minWidth: 500, minHeight: 360)
        }
    }
}
#endif
