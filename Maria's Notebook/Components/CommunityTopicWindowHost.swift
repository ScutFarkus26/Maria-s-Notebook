import CoreData
import SwiftUI

#if os(macOS)
struct CommunityTopicWindowHost: View {
    let topicID: UUID

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    var body: some View {
        let request: NSFetchRequest<CDCommunityTopicEntity> = {
            let request = NSFetchRequest<CDCommunityTopicEntity>(entityName: "CommunityTopic")
            request.predicate = NSPredicate(format: "id == %@", topicID as CVarArg)
            request.fetchLimit = 1
            return request
        }()

        if let topic = viewContext.safeFetchFirst(request) {
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
