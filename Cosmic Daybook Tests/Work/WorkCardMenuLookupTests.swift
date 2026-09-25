#if os(iOS)
import CoreData
import SwiftUI
import Testing
import UIKit
@testable import CosmicDaybook

/// Whether drawing a work card runs its menu's fan-out lookup.
///
/// `.contextMenu` calls its content closure with the card's body, so the status
/// submenus' group lookup — a fetch of every row on the card's lesson, then a
/// student fetch per linked copy — ran on every card body pass until it moved
/// into `WorkCardStatusMenu`'s body, which SwiftUI draws only when the menu is
/// built for display.
///
/// Detected through fresh contexts: each drawing context starts out holding one
/// work row, so any other row or any student it holds afterwards was fetched by
/// the draw.
@Suite("Work card menu lookup")
@MainActor
struct WorkCardMenuLookupTests {

    // MARK: - Fixture

    /// A three-child fan-out group, saved: one row per child, each naming all
    /// three, the shape `WorkGrouping` reads as linked copies.
    private func seedGroup(in context: NSManagedObjectContext) throws -> [CDWorkModel] {
        let lessonID = UUID()
        let studentIDs = try ["Ora", "Avital", "Leshem"].map { name in
            try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Peretz").id)
        }
        let works = studentIDs.map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Commutative law follow-up", studentID: studentID, lessonID: lessonID
            )
            work.kind = .followUpAssignment
            for peer in studentIDs {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = peer.uuidString
                participant.work = work
            }
            return work
        }
        try context.save()
        return works
    }

    /// A new main-queue context on `context`'s store, holding only `work`.
    private func drawingContext(
        for work: CDWorkModel, from context: NSManagedObjectContext
    ) throws -> (context: NSManagedObjectContext, work: CDWorkModel) {
        let drawing = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        drawing.persistentStoreCoordinator = context.persistentStoreCoordinator
        let copy = try #require(drawing.existing(CDWorkModel.self, work.objectID))
        return (drawing, copy)
    }

    /// The work rows besides `anchor`, and the students, `context` has fetched.
    private func fetched(
        in context: NSManagedObjectContext, besides anchor: CDWorkModel
    ) -> (works: Int, students: Int) {
        let registered = context.registeredObjects
        return (
            registered.filter { $0 is CDWorkModel && $0 !== anchor }.count,
            registered.filter { $0 is CDStudent }.count
        )
    }

    /// Puts `view` on screen in a window of its own; hide the window to finish.
    private func show(_ view: some View) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 640)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    /// Polls until `context` has fetched a row besides `anchor`, for up to ten seconds.
    private func waitForLookup(in context: NSManagedObjectContext, besides anchor: CDWorkModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while fetched(in: context, besides: anchor).works == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Tests

    @Test("Drawing a work card runs no group lookup; drawing its status menu does")
    func cardDrawRunsNoGroupLookup() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let works = try seedGroup(in: stack.viewContext)
        let card = try drawingContext(for: works[0], from: stack.viewContext)
        let menu = try drawingContext(for: works[0], from: stack.viewContext)
        let bulk = try drawingContext(for: works[0], from: stack.viewContext)

        let window = try show(VStack {
            WorkCard.grid(
                work: card.work,
                lessonTitle: "The Commutative Law",
                studentDisplay: "Ora P",
                needsAttention: false,
                ageSchoolDays: 3,
                onOpen: { _ in },
                onLog: { _, _ in },
                onSchedule: { _, _ in }
            )
            .environment(\.managedObjectContext, card.context)
            // The menu's status items drawn in the open, as the card's menu
            // used to resolve them on every card draw.
            WorkCardStatusMenu(
                work: menu.work, targets: [menu.work], isBulk: false, context: menu.context, onLog: { _, _ in }
            )
            // Part of a selection: the statuses act on it, with no lookup.
            WorkCardStatusMenu(
                work: bulk.work, targets: [bulk.work], isBulk: true, context: bulk.context, onLog: { _, _ in }
            )
        })
        defer { window.isHidden = true }

        // All three draw in the same pass.
        try await waitForLookup(in: menu.context, besides: menu.work)
        let menuFetched = fetched(in: menu.context, besides: menu.work)
        #expect(menuFetched.works == 2)
        #expect(menuFetched.students == 3)

        let cardFetched = fetched(in: card.context, besides: card.work)
        #expect(cardFetched.works == 0)
        #expect(cardFetched.students == 0)

        let bulkFetched = fetched(in: bulk.context, besides: bulk.work)
        #expect(bulkFetched.works == 0)
        #expect(bulkFetched.students == 0)
        withExtendedLifetime(stack) {}
    }
}
#endif
