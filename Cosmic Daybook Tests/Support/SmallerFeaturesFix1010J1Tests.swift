import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #88 and #90's resource delete: cancelled
/// going-outs could not be seen anywhere, and deleting a resource said it
/// deleted the file but left it in the Resource Files folder.
@Suite("Going Out and Resources (fix 10-10 J1)")
@MainActor
struct SmallerFeaturesFix1010J1Tests {

    @Test("Cancelled going-outs get a list of their own")
    func cancelledGoingOutsListed() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for (title, status) in [
            ("Library", GoingOutStatus.planning),
            ("Bakery", .completed),
            ("Zoo", .cancelled)
        ] {
            let goingOut = CDGoingOut(context: context)
            goingOut.title = title
            goingOut.status = status
        }
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = GoingOutViewModel()
        viewModel.loadData(context: context)

        #expect(viewModel.activeGoingOuts.map(\.title) == ["Library"])
        #expect(viewModel.completedGoingOuts.map(\.title) == ["Bakery"])
        #expect(viewModel.cancelledGoingOuts.map(\.title) == ["Zoo"])
    }

    @Test("Deleting a resource removes its file once no other resource uses it")
    func resourceDeleteRemovesFile() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let folder = try ResourceFileStorage.categoryDirectory(for: .other)
        let fileURL = folder.appendingPathComponent("Fix1010J1-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let relativePath = try ResourceFileStorage.relativePath(forManagedURL: fileURL)

        let original = CDResource(context: context)
        original.title = "Hundred board"
        original.fileRelativePath = relativePath
        let copy = CDResource(context: context)
        copy.title = "Hundred board (copy)"
        copy.fileRelativePath = relativePath
        #expect(CoreDataTestHelpers.save(context))
        let saver = SaveCoordinator.preview

        #expect(ResourceDeletion.delete([copy], context: context, saveCoordinator: saver))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        #expect(ResourceDeletion.delete([original], context: context, saveCoordinator: saver))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(context.safeFetch(CDFetchRequest(CDResource.self)).isEmpty)
    }
}
