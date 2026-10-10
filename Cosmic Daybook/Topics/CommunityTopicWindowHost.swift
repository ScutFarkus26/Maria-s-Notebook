import CoreData
import SwiftUI

#if os(macOS)
struct CommunityTopicWindowHost: View {
    let topicID: UUID

    var body: some View {
        EntityWindowHost(
            id: topicID,
            minSize: CGSize(width: 600, height: 500),
            notFound: WindowHostNotFound(
                "Topic Not Found",
                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                description: Text("This topic may have been deleted in another window."),
                minSize: CGSize(width: 500, height: 360)
            )
        ) { (topic: CDCommunityTopicEntity) in
            TopicDetailView(topic: topic)
            .navigationTitle(topic.title.isEmpty ? "Community Topic" : topic.title)
        }
    }
}
#endif
