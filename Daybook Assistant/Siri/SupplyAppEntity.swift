import AppIntents
import CoreData

/// A staple on the classroom's shelf, as Siri and Shortcuts name it: "We're
/// out of paper towels". A value snapshot of `CDSupply`; the Assistant's
/// Restock intents look the staple up again by `id` when they run.
struct SupplyAppEntity: AppEntity {
    let id: UUID
    let name: String
    let place: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Supply")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: place.isEmpty ? nil : "\(place)",
            image: .init(systemName: "shippingbox")
        )
    }

    static let defaultQuery = SupplyEntityQuery()
}

extension SupplyAppEntity {
    init?(staple: CDSupply) {
        guard let id = staple.id else { return nil }
        self.init(id: id, name: staple.name, place: staple.location)
    }
}

/// Finds staples for Siri: by id, by a spoken or typed name, and as the names
/// App Shortcut phrases learn (`updateAppShortcutParameters`).
struct SupplyEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SupplyAppEntity] {
        let wanted = Set(identifiers)
        return try Self.staples().filter { $0.id.map(wanted.contains) ?? false }.compactMap(SupplyAppEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SupplyAppEntity] {
        AssistantSupplyNames.matches(for: string, in: try Self.staples()).compactMap(SupplyAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SupplyAppEntity] {
        try Self.staples().compactMap(SupplyAppEntity.init)
    }

    /// The classroom's staples, from the classroom share's store.
    @MainActor
    private static func staples() throws -> [CDSupply] {
        let context = try AssistantStack.shared().viewContext
        return RestockService.staples(in: context, store: AssistantSiriRestock.sharedStore(of: context))
    }
}

/// Which staples a spoken name means. "paper towels", "Paper towel" and "the
/// paper towels" all find Paper Towels; with no such match, a name that holds
/// the words said ("towels" → Paper Towels), or that the words hold.
enum AssistantSupplyNames {
    static func matches(for spoken: String, in staples: [CDSupply]) -> [CDSupply] {
        let key = normalized(spoken)
        guard !key.isEmpty else { return [] }
        let exact = staples.filter { normalized($0.name) == key }
        if !exact.isEmpty { return exact }
        return staples.filter {
            let name = normalized($0.name)
            return !name.isEmpty && (contains(name, words: key) || contains(key, words: name))
        }
    }

    /// The one staple a spoken name means, for a command that acts on it
    /// without asking which: a staple of that very name, or the only one
    /// whose name holds the words (or that the words hold). Nil when the
    /// words are in several names ("paper": Paper Towels and Toilet Paper),
    /// or in none.
    static func match(for spoken: String, in staples: [CDSupply]) -> CDSupply? {
        let found = matches(for: spoken, in: staples)
        let key = normalized(spoken)
        if let exact = found.first(where: { normalized($0.name) == key }) { return exact }
        return found.count == 1 ? found.first : nil
    }

    /// Folded, without a leading "the", "some" or "more", and each word
    /// without a plural "s" or "es".
    static func normalized(_ text: String) -> String {
        var words = text.foldedKey()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        while let first = words.first, ["the", "some", "more", "a", "an"].contains(first), words.count > 1 {
            words.removeFirst()
        }
        return words.map(singular).joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Whether `text`'s words include `words`, in order and whole.
    private static func contains(_ text: String, words: String) -> Bool {
        " \(text) ".contains(" \(words) ")
    }
}
