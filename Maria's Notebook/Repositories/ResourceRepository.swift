import Foundation
import OSLog
import CoreData

@MainActor
struct ResourceRepository: SavingRepository {
    typealias Model = CDResource

    private static let logger = Logger.resources

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    func fetchResource(id: UUID) -> CDResource? {
        let request = CDFetchRequest(CDResource.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    func fetchResources(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDResource] {
        let request = CDFetchRequest(CDResource.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    func fetchResources(byCategory category: String) -> [CDResource] {
        fetchResources(predicate: NSPredicate(format: "categoryRaw == %@", category))
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

    // MARK: - Update

    func markViewed(id: UUID) {
        guard let resource = fetchResource(id: id) else { return }
        resource.lastViewedAt = Date()
    }

    // MARK: - Delete

    func deleteResource(_ resource: CDResource) {
        if !resource.fileRelativePath.isEmpty {
            do {
                let fileURL = try ResourceFileStorage.resolve(relativePath: resource.fileRelativePath)
                try ResourceFileStorage.deleteIfManaged(fileURL)
            } catch {
                Self.logger.warning("Failed to delete resource file: \(error, privacy: .public)")
            }
        }
        context.delete(resource)
    }
}
