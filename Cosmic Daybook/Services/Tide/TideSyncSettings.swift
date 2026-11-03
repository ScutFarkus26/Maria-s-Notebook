// TideSyncSettings.swift
// What Danny chose in Settings › Connections › Tide, and what the sync
// remembers between runs.

import Foundation

/// Danny's choices for the sharing, kept in UserDefaults on this Mac.
nonisolated struct TideSyncSettings: Equatable, Sendable {
    /// The Tide area whose lists the notebook reads and shows.
    static let area = "My Classrooms"
    static let defaultDestination = "Areas/My Classrooms/Upper Elementary/To do.md"

    var isOn = false
    /// Where new notebook to-dos go.
    var destinationFile = Self.defaultDestination
    /// The heading they go under; nil for the list's first heading.
    var destinationHeading: String?
    /// The lists whose to-dos show in the notebook; nil for every list of the area.
    var shownLists: Set<String>?

    init() {}

    init(defaults: UserDefaults) {
        isOn = defaults.bool(forKey: UserDefaultsKeys.tideSyncOn)
        destinationFile = defaults.string(forKey: UserDefaultsKeys.tideDestinationFile) ?? Self.defaultDestination
        destinationHeading = defaults.string(forKey: UserDefaultsKeys.tideDestinationHeading)
        shownLists = defaults.stringArray(forKey: UserDefaultsKeys.tideShownLists).map(Set.init)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(isOn, forKey: UserDefaultsKeys.tideSyncOn)
        defaults.set(destinationFile, forKey: UserDefaultsKeys.tideDestinationFile)
        if let destinationHeading {
            defaults.set(destinationHeading, forKey: UserDefaultsKeys.tideDestinationHeading)
        } else {
            defaults.removeObject(forKey: UserDefaultsKeys.tideDestinationHeading)
        }
        if let shownLists {
            defaults.set(shownLists.sorted(), forKey: UserDefaultsKeys.tideShownLists)
        } else {
            defaults.removeObject(forKey: UserDefaultsKeys.tideShownLists)
        }
    }

    /// Whether `file`'s to-dos show in the notebook.
    func shows(_ file: String) -> Bool {
        shownLists?.contains(file) ?? true
    }
}

/// What the sync remembers between runs, in UserDefaults on this Mac, per
/// CloudKit environment's notebook. Bounded by the open to-dos: an entry
/// goes when its to-do is closed on both sides or gone; `unmarkedLinks`, by
/// Tide's open actions instead, and `pendingTicks` once its tick has gone.
nonisolated struct TideSyncState: Equatable, Sendable {
    /// The linked to-dos (uuid strings) both apps last agreed were open. A
    /// tick is carried only from here, so an untick on either side is never
    /// carried and a tick never twice. Only `true` is kept: a to-do closed on
    /// both sides, or one the sync knows nothing about, has no entry.
    var agreedOpen: [String: Bool] = [:]
    /// The linked to-dos (uuid strings) that were made from a Tide action:
    /// they follow Tide's words and due date.
    var fromTide: Set<String> = []
    /// When Danny confirmed the first run's matches; nil before.
    var firstRunConfirmedAt: Date?
    /// The to-dos the first run linked (uuid strings).
    var firstRunLinked: [String] = []
    /// Linked to-dos (uuid string) whose action's note doesn't carry the
    /// notebook line yet, with the action's address. Kept after the to-do
    /// goes: deleted here, it would otherwise come back on the next run, as
    /// its action looks like one made in Tide (bug hunt 2026-10-29). An
    /// entry goes when its action is marked, or gone from Tide's lists.
    var unmarkedLinks: [String: String] = [:]
    /// Tide's due date ("YYYY-MM-DD", "" for none) of each linked to-do both
    /// apps last agreed was open, as the last run that saw both open read
    /// it: what an edit to the date on either side is measured from, and how
    /// a repeat ticked in Tide too is told from one still to tick (bug hunt
    /// 2026-11-02 #3, #46).
    var agreedDue: [String: String] = [:]
    /// Linked to-dos (uuid string → their action's address) ticked here
    /// while both apps last agreed they were open, whose tick hasn't reached
    /// Tide yet. Kept after the to-do goes: cleared or deleted before the Mac
    /// told Tide, the tick still goes across (bug hunt 2026-11-02 #11).
    var pendingTicks: [String: String] = [:]
    var lastSyncAt: Date?

    /// Named and scoped per CloudKit environment as the keys in
    /// `UserDefaultsKeys+Tide` are.
    private static var agreedDueKey: String { CloudKitEnvironment.scoped("Tide.agreedDue") }
    private static var pendingTicksKey: String { CloudKitEnvironment.scoped("Tide.pendingTicks") }

    init() {}

    init(defaults: UserDefaults) {
        agreedOpen = defaults.dictionary(forKey: UserDefaultsKeys.tideLinkStates) as? [String: Bool] ?? [:]
        fromTide = Set(defaults.stringArray(forKey: UserDefaultsKeys.tideFromTide) ?? [])
        firstRunConfirmedAt = defaults.object(forKey: UserDefaultsKeys.tideFirstRunConfirmedAt) as? Date
        firstRunLinked = defaults.stringArray(forKey: UserDefaultsKeys.tideFirstRunLinked) ?? []
        unmarkedLinks = defaults.dictionary(forKey: UserDefaultsKeys.tideUnmarkedLinks) as? [String: String] ?? [:]
        agreedDue = defaults.dictionary(forKey: Self.agreedDueKey) as? [String: String] ?? [:]
        pendingTicks = defaults.dictionary(forKey: Self.pendingTicksKey) as? [String: String] ?? [:]
        lastSyncAt = defaults.object(forKey: UserDefaultsKeys.tideLastSyncAt) as? Date
    }

    func save(to defaults: UserDefaults) {
        defaults.set(agreedOpen, forKey: UserDefaultsKeys.tideLinkStates)
        defaults.set(fromTide.sorted(), forKey: UserDefaultsKeys.tideFromTide)
        defaults.set(firstRunConfirmedAt, forKey: UserDefaultsKeys.tideFirstRunConfirmedAt)
        defaults.set(firstRunLinked, forKey: UserDefaultsKeys.tideFirstRunLinked)
        defaults.set(unmarkedLinks, forKey: UserDefaultsKeys.tideUnmarkedLinks)
        defaults.set(agreedDue, forKey: Self.agreedDueKey)
        defaults.set(pendingTicks, forKey: Self.pendingTicksKey)
        defaults.set(lastSyncAt, forKey: UserDefaultsKeys.tideLastSyncAt)
    }

    /// Whether both apps last agreed the to-do was open; setting false or nil
    /// forgets it.
    subscript(todo id: UUID) -> Bool {
        get { agreedOpen[id.uuidString] == true }
        set { agreedOpen[id.uuidString] = newValue ? true : nil }
    }

    /// The to-dos with a tick that may still have to go across.
    var openIDs: Set<UUID> { Set(agreedOpen.keys.compactMap(UUID.init(uuidString:))) }

    /// Forgets every to-do not among `ids`. `unmarkedLinks` outlives its
    /// to-do (`keepUnmarkedLinks`), and so does a tick still to go across;
    /// for a to-do still here, the tick goes the usual way while it is
    /// agreed open.
    mutating func keep(only ids: Set<UUID>) {
        let kept = Set(ids.map(\.uuidString))
        agreedOpen = agreedOpen.filter { kept.contains($0.key) && $0.value }
        fromTide = fromTide.intersection(kept)
        pendingTicks = pendingTicks.filter { !kept.contains($0.key) || agreedOpen[$0.key] == true }
        agreedDue = agreedDue.filter { agreedOpen[$0.key] == true || pendingTicks[$0.key] != nil }
    }

    /// Forgets each unmarked link whose address isn't among `addresses`
    /// (every action of this read): its action is gone from Tide's lists.
    mutating func keepUnmarkedLinks(at addresses: Set<String>) {
        unmarkedLinks = unmarkedLinks.filter { addresses.contains($0.value) }
    }
}
