import Foundation
import OSLog
import SwiftData

@MainActor
struct ResourceRepository: SavingRepository {
    typealias Model = Resource

    private static let logger = Logger.resources

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    func fetchResource(id: UUID) -> Resource? {
        var descriptor = FetchDescriptor<Resource>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    func fetchResources(
        predicate: Predicate<Resource>? = nil,
        sortBy: [SortDescriptor<Resource>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [Resource] {
        var descriptor = FetchDescriptor<Resource>()
        if let predicate { descriptor.predicate = predicate }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    func fetchResources(byCategory category: String) -> [Resource] {
        let predicate = #Predicate<Resource> { $0.categoryRaw == category }
        return fetchResources(predicate: predicate)
    }

    func fetchFavorites() -> [Resource] {
        let predicate = #Predicate<Resource> { $0.isFavorite == true }
        return fetchResources(predicate: predicate)
    }

    func fetchRecents(limit: Int = 20) -> [Resource] {
        var descriptor = FetchDescriptor<Resource>(
            predicate: #Predicate { $0.lastViewedAt != nil },
            sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return context.safeFetch(descriptor)
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
        linkedSubjects: String = ""
    ) -> Resource {
        let resource = Resource(
            title: title,
            descriptionText: descriptionText,
            category: category,
            fileBookmark: fileBookmark,
            fileRelativePath: fileRelativePath,
            fileSizeBytes: fileSizeBytes,
            thumbnailData: thumbnailData,
            tags: tags,
            linkedLessonIDs: linkedLessonIDs,
            linkedSubjects: linkedSubjects
        )
        context.insert(resource)
        return resource
    }

    // MARK: - Update

    @discardableResult
    func updateResource(
        id: UUID,
        title: String? = nil,
        category: ResourceCategory? = nil,
        descriptionText: String? = nil,
        tags: [String]? = nil,
        isFavorite: Bool? = nil,
        linkedLessonIDs: String? = nil,
        linkedSubjects: String? = nil
    ) -> Bool {
        guard let resource = fetchResource(id: id) else { return false }

        if let title { resource.title = title }
        if let category { resource.category = category }
        if let descriptionText { resource.descriptionText = descriptionText }
        if let tags { resource.tags = tags }
        if let isFavorite { resource.isFavorite = isFavorite }
        if let linkedLessonIDs { resource.linkedLessonIDs = linkedLessonIDs }
        if let linkedSubjects { resource.linkedSubjects = linkedSubjects }
        resource.modifiedAt = Date()

        return true
    }

    func markViewed(id: UUID) {
        guard let resource = fetchResource(id: id) else { return }
        resource.lastViewedAt = Date()
    }

    // MARK: - Delete

    func deleteResource(_ resource: Resource) {
        // Clean up file from storage
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
