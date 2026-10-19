// ClassGridScope.swift
// What carries across the Class Grid's four views: the area menu, the search
// text and the children filter (canvas note, "What this replaces"). Display
// only; nothing here touches a record.
//
// The area is nil for "All areas". The Checklist always shows one area, so it
// keeps its own (`checklistArea`, remembered under the key the Checklist has
// always used); picking an area in any view sets both, and "All areas" in
// another view leaves the Checklist on the area it last showed.

import CoreData
import Foundation

@Observable
final class ClassGridScope {
    /// The area the menu shows outside the Checklist; nil is "All areas".
    var area: String?
    /// The one area the Checklist shows when `area` is nil.
    private(set) var checklistArea: String
    /// Every area with a lesson, in the Lessons screen's saved order.
    private(set) var areas: [String] = []
    /// Lessons on the Checklist, children on Children, lessons and children on
    /// Recall (Mac and iPad). Three Years and the iPhone's Recall show no field,
    /// so they ignore it (`query(for:isRegular:)`) and keep it for the way back.
    var searchText = ""
    /// What `searchText` looks through: the target of the last view that showed
    /// a field.
    private(set) var searchTarget: ClassGridSearchTarget?
    /// The Checklist's lens, kept while another view shows; the grid opens on
    /// All marks.
    var checklistLens: ChecklistLens = .allMarks
    /// Empty shows every child.
    var childFilterIDs: Set<UUID> = []
    /// The enrolled children the filter offers, test students left out.
    private(set) var roster: [CDStudent] = []

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        checklistArea = defaults.string(forKey: UserDefaultsKeys.checklistSelectedArea) ?? ""
    }

    // MARK: - Area

    /// The menu's title in `view`: the Checklist's one area, or the area (or
    /// "All areas") the others show.
    func menuTitle(for view: ClassGridViewKind) -> String {
        if view == .checklist {
            let shown = checklistAreaToShow
            return shown.isEmpty ? "Area" : shown
        }
        return area ?? "All areas"
    }

    /// The menu's checked item in `view`.
    func menuSelection(for view: ClassGridViewKind) -> String? {
        view == .checklist ? checklistAreaToShow : area
    }

    /// The area the Checklist opens on: the one picked anywhere in the grid,
    /// else the one it showed last, else the first area.
    var checklistAreaToShow: String {
        if let area, !area.isEmpty { return area }
        if !checklistArea.isEmpty { return checklistArea }
        return areas.first ?? ""
    }

    /// A pick from the area menu. Nil ("All areas") changes only the views
    /// that can show it.
    func pick(area newValue: String?) {
        area = newValue
        if let newValue, !newValue.isEmpty { rememberChecklistArea(newValue) }
    }

    /// The Checklist moved to `newValue` itself (a deep link, or its own load
    /// falling back to the first area): the menu follows it.
    func checklistDidShow(area newValue: String) {
        guard !newValue.isEmpty else { return }
        if area != nil, area != newValue { area = newValue }
        rememberChecklistArea(newValue)
    }

    private func rememberChecklistArea(_ value: String) {
        guard checklistArea != value else { return }
        checklistArea = value
        defaults.set(value, forKey: UserDefaultsKeys.checklistSelectedArea)
    }

    // MARK: - Search

    /// The search field's prompt in `view`.
    func searchPrompt(for view: ClassGridViewKind) -> String {
        switch view {
        case .checklist:
            let shown = checklistAreaToShow
            return shown.isEmpty ? "Search lessons" : "Search \(shown)"
        case .threeYears: return "Search lessons"
        case .children: return "Search children"
        case .recall: return "Search"
        }
    }

    /// The grid now shows `view`. A view with no field leaves the search alone;
    /// a field that looks through something else than the search was typed for
    /// starts empty, so a child's name never becomes a lesson search.
    func viewDidChange(to view: ClassGridViewKind, isRegular: Bool) {
        guard let target = view.searchTarget(isRegular: isRegular) else { return }
        if let searchTarget, searchTarget != target, !searchText.isEmpty { searchText = "" }
        searchTarget = target
    }

    /// The search `view` applies: none where it shows no field to see or clear it.
    func query(for view: ClassGridViewKind, isRegular: Bool) -> String {
        view.searchTarget(isRegular: isRegular) == nil ? "" : searchText
    }

    /// Whether the children filter keeps `studentID`.
    func showsChild(_ studentID: UUID) -> Bool {
        childFilterIDs.isEmpty || childFilterIDs.contains(studentID)
    }

    // MARK: - Loading

    /// The areas and the roster, read once when the grid opens: one distinct
    /// fetch of lesson areas and one of the enrolled children.
    func load(context: NSManagedObjectContext, showTestStudents: Bool, testNamesRaw: String) {
        areas = Self.orderedAreas(in: context)
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let enrolled = context.safeFetch(request).sorted(by: ClassAreaChecklistViewModel.rosterOrder)
        roster = TestStudentsFilter.filterVisible(enrolled, show: showTestStudents, namesRaw: testNamesRaw)
        let known = Set(roster.compactMap(\.id))
        if !childFilterIDs.isSubset(of: known) { childFilterIDs.formIntersection(known) }
    }

    /// Every lesson area, trimmed, in the Lessons screen's saved order.
    static func orderedAreas(in context: NSManagedObjectContext) -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: CDLesson.entity().name ?? "Lesson")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["area"]
        request.returnsDistinctResults = true
        let raw = (try? context.fetch(request)) ?? []
        let unique = Set(raw.compactMap { ($0["area"] as? String)?.trimmed() }.filter { !$0.isEmpty })
        let existing = unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }
}
