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

    var context: NSManagedObjectContext { stack.viewContext }

    /// The app's stack, once the phone has joined a class.
    init() throws {
        let stack = try SiriHost.stack()
        try SiriHost.checkReady(in: stack.viewContext)
        self.init(stack: stack, author: RestockAuthor.current(role: .assistant))
    }

    /// Tests pass an in-memory stack and an author.
    init(stack: CoreDataStack, author: RestockAuthor) {
        self.stack = stack
        self.author = author
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

        var dialog: IntentDialog {
            IntentDialog(full: "\(spoken)", supporting: "\(summary)")
        }

        /// What Siri says.
        var spoken: String {
            switch self {
            case let .marked(name, level, source):
                let list = source == .office ? "It's on the office run." : "It's on your guide's order list."
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
        RestockService.setLevel(staple, to: level, by: author, in: context)
        try commit()
        return .marked(staple.name, level, staple.source)
    }

    /// "Add ‹thing› to the office run": a staple of that name is marked Low
    /// (it's on the office run, or the order list for one that's ordered);
    /// anything else becomes a one-off from the office.
    func addToOfficeRun(_ spoken: String) throws -> Outcome {
        let name = spoken.trimmed()
        guard !name.isEmpty else { throw AssistantRestockSiriError.noName }
        let staples = RestockService.staples(in: context, store: Self.sharedStore(of: context))
        if let staple = AssistantSupplyNames.matches(for: name, in: staples).first {
            guard staple.level == .stocked else { return .already(staple.name, staple.level) }
            RestockService.setLevel(staple, to: .low, by: author, in: context)
            try commit()
            return .marked(staple.name, .low, staple.source)
        }
        guard let added = RestockService.addOneOff(title: name, source: .office, by: author, in: context) else {
            throw AssistantRestockSiriError.noName
        }
        guard added.isNew else { return .alreadyListed(added.object.displayTitle) }
        try commit()
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
    /// without holding up Siri's answer, and tells an open Restock tab.
    private func commit() throws {
        let created = context.insertedObjects.filter {
            AssistantRestockModel.restockEntities.contains($0.entity.name ?? "")
        }
        guard context.safeSave() else {
            context.rollback()
            throw AssistantRestockSiriError.saveFailed
        }
        // After the save: a new record's ID is only permanent from here.
        let ids = created.map(\.objectID)
        let stack = self.stack
        SiriSyncKeepAlive.run(named: "Siri restock sync") {
            await SiriHost.didSave(created: ids, in: stack)
        }
        NotificationCenter.default.post(name: .restockChangedBySiri, object: nil)
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
