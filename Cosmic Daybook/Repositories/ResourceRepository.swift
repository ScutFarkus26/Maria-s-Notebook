import Foundation
import OSLog
import CoreData

struct ResourceRepository: SavingRepository {
    typealias Model = CDResource

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Create

    @discardableResult
    func createResource(
        title: String,
        category: ResourceCategory,
        descriptionText: String = "",
        fileBookmark: Data? = nil,
        fileRelativePath: String = "",
        fileSizeBytes: Int64 = 0,
        thumbnailData: Data? = nil,
        tags: [String] = [],
        linkedLessonIDs: String = "",
        linkedAreas: String = ""
    ) -> CDResource {
        let resource = CDResource(context: context)
        resource.title = title
        resource.category = category
        resource.descriptionText = descriptionText
        resource.fileBookmark = fileBookmark
        resource.fileRelativePath = fileRelativePath
        resource.fileSizeBytes = fileSizeBytes
        resource.thumbnailData = thumbnailData
        resource.tagsArray = tags
        resource.linkedLessonIDs = linkedLessonIDs
        resource.linkedAreas = linkedAreas
        return resource
    }
}
