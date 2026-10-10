import CoreData
import Foundation
import OSLog

/// Deleting resources together with their files.
///
/// Delete promised to remove "the resource and its file" but removed only the
/// record, leaving the file in the Resource Files folder. The file goes now,
/// but only after the deletion is saved (a failed save leaves both), and only
/// when no other resource still points at the same file.
enum ResourceDeletion {

    /// Deletes `resources`, saves, and then removes each file no remaining
    /// resource uses. Returns whether the save succeeded.
    @discardableResult
    static func delete(
        _ resources: [CDResource],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> Bool {
        let paths = Set(resources.map(\.fileRelativePath).filter { !$0.isEmpty })
        for resource in resources {
            context.delete(resource)
        }
        guard saveCoordinator.save(
            context, reason: resources.count == 1 ? "Delete resource" : "Delete resources"
        ) else {
            return false
        }
        removeUnusedFiles(atRelativePaths: paths, context: context)
        return true
    }

    /// Removes the managed file at each path that no resource refers to any more.
    static func removeUnusedFiles(atRelativePaths paths: Set<String>, context: NSManagedObjectContext) {
        for path in paths where !isInUse(relativePath: path, context: context) {
            guard let url = ResourceFileStorage.fileURL(relativePath: path),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try ResourceFileStorage.storage.deleteIfManaged(url)
            } catch {
                Logger.resources.warning(
                    "Couldn't remove a deleted resource's file: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Whether any resource still stored keeps its file at `relativePath`.
    static func isInUse(relativePath: String, context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDResource.self)
        request.predicate = NSPredicate(format: "fileRelativePath == %@", relativePath)
        return context.safeFetch(request).contains { !$0.isDeleted }
    }
}
