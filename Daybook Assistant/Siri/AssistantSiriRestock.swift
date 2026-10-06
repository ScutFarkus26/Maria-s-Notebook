import AppIntents
import CoreData

/// The work behind the Assistant's Restock commands ("We're out of paper
/// towels", "We're low on tissues", "Add glue sticks to the office run"),
/// apart from Siri's answers, so tests can run it on an in-memory stack.
/// Every change goes through `RestockService`, as a tap on the shelf does, and
/// what a save creates goes into the classroom share through `SiriHost.didSave`.
@MainActor
struct AssistantSiriRestock {
    let stack: CoreDataStack
    let author: RestockAuthor
    /// Saves the context; true when it worked.
    private let save: @MainActor (NSManagedObjectContext) -> Bool

    var context: NSManagedObjectContext { stack.viewContext }

    /// The app's stack, once the phone has joined a class.
    init() throws {
        let stack = try AssistantStack.shared()
        try SiriHost.checkReady(in: stack.viewContext)
        let names = ClassroomNames.snapshot(in: stack.viewContext)
        self.init(stack: stack, author: RestockAuthor.current(role: .assistant).reading(names))
    }

    /// The name the guide set in the classroom's list, for "It's on Danny's
    /// order list". Siri reads the list itself; Apple's name for the share's
    /// owner comes only with the app's sharing service, which Siri doesn't open.
    var guideName: String? { author.names.guideName }

    /// Tests pass an in-memory stack and an author, and a save that fails.
    init(
        stack: CoreDataStack,
        author: RestockAuthor,
        save: @escaping @MainActor (NSManagedObjectContext) -> Bool = { $0.safeSave() }
    ) {
        self.stack = stack
        self.author = author
        self.save = save
    }

    /// The classroom share's store; nil with one store (the sample class, tests).
    static func sharedStore(of context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    /// What a command did, and how Siri says it.
    enum Outcome: Equatable {
        /// The staple is now at this level; its need is on the office run or the order list.
        case marked(String, RestockLevel, RestockSource)
        /// It was already at that level (or Out, asked to be Low); nothing changed.
        case already(String, RestockLevel)
        /// A new one-off on the office run.
        case added(String)
        /// That one-off was already on the office run.
        case alreadyListed(String)

        /// What Siri says and shows, naming the guide (`guideName`) when he
        /// set a name.
        func dialog(guideName: String?) -> IntentDialog {
            IntentDialog(full: "\(spoken(guideName: guideName))", supporting: "\(summary)")
        }

        /// What Siri says: "It's on Danny's order list", or "your guide's"
        /// without his name.
        func spoken(guideName: String? = nil) -> String {
            switch self {
            case let .marked(name, level, source):
                let guides = guideName.map { "\($0)'s" } ?? "your guide's"
                let list = source == .office ? "It's on the office run." : "It's on \(guides) order list."
                return "\(name) is marked \(level.displayName.lowercased()). \(list)"
            case let .already(name, level):
                return "\(name) was already marked \(level.displayName.lowercased())."
            case let .added(name):
                return "\(name) is on the office run."
            case let .alreadyListed(name):
                return "\(name) is already on the office run."
            }
        }

        /// What Siri shows under it.
        var summary: String {
            switch self {
            case let .marked(_, level, _): level.displayName
            case let .already(_, level): "Already \(level.displayName.lowercased())"
            case .added: "On the office run"
            case .alreadyListed: "Already on the office run"
            }
        }
    }

    // MARK: - Commands

    /// "We're out of" / "We're low on": sets the staple's level. Low never
    /// takes an Out staple back up; that's the shelf's hold menu or a check-off.
    func mark(_ supplyID: UUID, as level: RestockLevel) throws -> Outcome {
        guard let staple = staple(id: supplyID) else { throw AssistantRestockSiriError.notFound }
        if staple.level == level || (level == .low && staple.level == .out) {
            return .already(staple.name, staple.level)
        }
        let change = SiriChange(in: context)
        RestockService.setLevel(staple, to: level, by: author, in: context)
        try commit(change)
        return .marked(staple.name, level, staple.source)
    }

    /// "Add ‹thing› to the office run": the one staple that name means is
    /// marked Low (it's on the office run, or the order list for one that's
    /// ordered); anything else, a name in several staples' names included,
    /// becomes a one-off from the office rather than a guess at one of them.
    func addToOfficeRun(_ spoken: String) throws -> Outcome {
        let name = spoken.trimmed()
        guard !name.isEmpty else { throw AssistantRestockSiriError.noName }
        let staples = RestockService.staples(in: context, store: Self.sharedStore(of: context))
        if let staple = AssistantSupplyNames.match(for: name, in: staples) {
            guard staple.level == .stocked else { return .already(staple.name, staple.level) }
            let change = SiriChange(in: context)
            RestockService.setLevel(staple, to: .low, by: author, in: context)
            try commit(change)
            return .marked(staple.name, .low, staple.source)
        }
        let change = SiriChange(in: context)
        guard let added = RestockService.addOneOff(title: name, source: .office, by: author, in: context) else {
            change.end()
            throw AssistantRestockSiriError.noName
        }
        guard added.isNew else {
            change.end()
            return .alreadyListed(added.object.displayTitle)
        }
        try commit(change)
        return .added(added.object.displayTitle)
    }

    // MARK: - Steps

    private func staple(id: UUID) -> CDSupply? {
        let request = CDFetchRequest(CDSupply.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let store = Self.sharedStore(of: context) { request.affectedStores = [store] }
        return context.safeFetchFirst(request)
    }

    /// Saves, then sends what the save created into the classroom share
    /// without holding up Siri's answer, and tells an open Restock tab. A
    /// save that fails takes back Siri's `change` alone: the tab's taps still
    /// waiting for their own save in the same context stay, and the tab
    /// reloads to show them without Siri's.
    private func commit(_ change: SiriChange) throws {
        let created = context.insertedObjects.filter {
            AssistantRestockModel.restockEntities.contains($0.entity.name ?? "")
        }
        guard save(context) else {
            change.takeBack()
            NotificationCenter.default.post(name: .restockChangedBySiri, object: nil)
            throw AssistantRestockSiriError.saveFailed
        }
        change.end()
        // After the save: a new record's ID is only permanent from here.
        let ids = created.map(\.objectID)
        let stack = self.stack
        SiriSyncKeepAlive.run(named: "Siri restock sync") {
            await SiriHost.didSave(created: ids, in: stack)
        }
        NotificationCenter.default.post(name: .restockChangedBySiri, object: nil)
    }
}

/// The changes one Siri command makes to a context that may already hold the
/// Restock tab's unsaved taps: recorded by a temporary undo manager from its
/// start, so a failed save can take back these and nothing else, where
/// `rollback()` would drop the tab's taps too. As the notebook's
/// `ContextMutationTransaction` does, which this app doesn't compile.
@MainActor
private final class SiriChange {
    private let context: NSManagedObjectContext
    private let previous: UndoManager?
    private let undo = UndoManager()
    private var isDone = false

    init(in context: NSManagedObjectContext) {
        self.context = context
        // The tab's changes so far are settled first, so none is recorded.
        context.processPendingChanges()
        previous = context.undoManager
        undo.groupsByEvent = false
        context.undoManager = undo
        undo.beginUndoGrouping()
    }

    /// Keeps the change (saved, or nothing to save).
    func end() {
        finishRecording()
        undo.removeAllActions()
        context.undoManager = previous
    }

    /// Undoes the change.
    func takeBack() {
        finishRecording()
        if undo.canUndo {
            undo.undo()
            context.processPendingChanges()
        }
        undo.removeAllActions()
        context.undoManager = previous
    }

    private func finishRecording() {
        guard !isDone else { return }
        isDone = true
        context.processPendingChanges()
        if undo.groupingLevel > 0 { undo.endUndoGrouping() }
    }
}

enum AssistantRestockSiriError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notFound
    case noName
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: "I couldn't find that on the shelf."
        case .noName: "I didn't catch what we need."
        case .saveFailed: "Something went wrong saving that. Please try again."
        }
    }
}
