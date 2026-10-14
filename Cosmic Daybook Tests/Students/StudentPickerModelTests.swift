import Foundation
import Testing
@testable import CosmicDaybook

/// The picker's rules, without a store: who is offered, in what order, who may
/// not be ticked, and what the record caption says.
@Suite("Student Picker Rows")
struct StudentPickerModelTests {

    private func candidate(
        _ first: String,
        _ last: String,
        birthday: Date? = nil,
        level: CDStudent.Level = .upper,
        status: CDStudent.EnrollmentStatus = .enrolled,
        departedOn: Date? = nil
    ) -> StudentPickerCandidate {
        StudentPickerCandidate(
            id: UUID(),
            firstName: first,
            lastName: last,
            birthday: birthday,
            level: level,
            status: status,
            departedOn: departedOn
        )
    }

    private func day(_ text: String) throws -> Date {
        try #require(DateFormatters.isoDate.date(from: text))
    }

    private func rows(
        _ candidates: [StudentPickerCandidate],
        search: String = "",
        scope: StudentPickerModel.LevelScope = .all,
        sort: StudentPickerModel.Sort = .name,
        records: [UUID: PresentationRecordIndex.Given] = [:],
        formerStudents: StudentPickerModel.FormerStudents = .hidden
    ) -> [StudentPickerRow] {
        StudentPickerModel.rows(
            candidates: candidates,
            query: StudentPickerModel.Query(
                search: search, scope: scope, sort: sort, formerStudents: formerStudents
            ),
            records: records
        )
    }

    // MARK: - Search and scope

    @Test("search matches first name, last name and the full name, ignoring case")
    func searchMatchesEitherName() {
        let people = [candidate("Naomi", "Levin"), candidate("Etty", "Dechter")]

        #expect(rows(people, search: "nao").map(\.candidate.firstName) == ["Naomi"])
        #expect(rows(people, search: "DECHTER").map(\.candidate.firstName) == ["Etty"])
        #expect(rows(people, search: "naomi lev").map(\.candidate.firstName) == ["Naomi"])
        #expect(rows(people, search: "  ").count == 2)
        #expect(rows(people, search: "zzz").isEmpty)
    }

    @Test("a level scope keeps only that level")
    func levelScopeNarrows() {
        let people = [
            candidate("Naomi", "Levin", level: .upper),
            candidate("Etty", "Dechter", level: .adolescent)
        ]

        #expect(rows(people, scope: .level(.adolescent)).map(\.candidate.firstName) == ["Etty"])
        #expect(rows(people, scope: .all).count == 2)
    }

    // MARK: - Order

    @Test("name sort runs first name then last name")
    func nameSort() {
        let people = [
            candidate("Etty", "Krinsky"),
            candidate("Etty", "Dechter"),
            candidate("avital", "Beyderman")
        ]

        let order = rows(people, sort: .name).map(\.candidate.lastName)
        #expect(order == ["Beyderman", "Dechter", "Krinsky"])
    }

    @Test("age sort runs oldest first and sinks a child with no birthday")
    func ageSortOldestFirstNilLast() throws {
        let people = [
            candidate("Younger", "Child", birthday: try day("2018-04-02")),
            candidate("Unknown", "Birthday"),
            candidate("Older", "Child", birthday: try day("2016-09-30"))
        ]

        let order = rows(people, sort: .age).map(\.candidate.firstName)
        #expect(order == ["Older", "Younger", "Unknown"])
    }

    // MARK: - A child who has left

    @Test("a withdrawn child is dropped by default and listed, blocked, for a lesson")
    func formerStudentsPolicy() throws {
        let departed = try day("2026-06-12")
        let people = [
            candidate("Naomi", "Levin", status: .withdrawn, departedOn: departed),
            candidate("Etty", "Dechter")
        ]

        #expect(rows(people).map(\.candidate.firstName) == ["Etty"])

        let shown = rows(people, formerStudents: .shownBlocked)
        let naomi = try #require(shown.first { $0.candidate.firstName == "Naomi" })
        #expect(naomi.block == .withdrawn(on: departed))
        #expect(!naomi.isSelectable)
        #expect(shown.first { $0.candidate.firstName == "Etty" }?.isSelectable == true)
    }

    @Test("the block says what happened and when, in the picker's words")
    func blockReason() throws {
        let departed = try day("2026-06-12")
        let withdrawn = try #require(
            StudentEnrollmentBlock.forStatus(.withdrawn, departedOn: departed)
        )
        #expect(withdrawn.shortReason == "Withdrawn \(DateFormatters.mediumDate.string(from: departed))")

        let transferred = try #require(StudentEnrollmentBlock.forStatus(.transferred, departedOn: nil))
        #expect(transferred.shortReason == "Transferred")
        #expect(StudentEnrollmentBlock.forStatus(.enrolled, departedOn: departed) == nil)
    }

    @Test("the refusal names her, her status and the day she left")
    func refusalWording() {
        let block = StudentEnrollmentBlock.withdrawn(on: nil)
        #expect(block.refusal(name: "Naomi Levin", action: "scheduled for a presentation",
                              departedDay: "2026-06-12")
            == "Naomi Levin is withdrawn (departed 2026-06-12) and cannot be scheduled for a presentation.")
        #expect(block.refusal(name: "Naomi Levin", action: "scheduled for a presentation", departedDay: nil)
            == "Naomi Levin is withdrawn and cannot be scheduled for a presentation.")
        #expect(StudentEnrollmentBlock.transferred(on: nil)
            .listEntry(name: "Rivka Stein", departedDay: nil) == "Rivka Stein (transferred)")
    }

    // MARK: - Selection

    @Test("tapping never adds a blocked child, but always removes one already selected")
    func togglingRespectsBlocks() throws {
        let naomi = candidate("Naomi", "Levin", status: .withdrawn, departedOn: nil)
        let etty = candidate("Etty", "Dechter")
        let listed = rows([naomi, etty], formerStudents: .shownBlocked)

        #expect(StudentPickerModel.toggling(naomi.id, in: [], rows: listed).isEmpty)
        #expect(StudentPickerModel.toggling(naomi.id, in: [naomi.id, etty.id], rows: listed) == [etty.id])
        #expect(StudentPickerModel.toggling(etty.id, in: [], rows: listed) == [etty.id])
        #expect(StudentPickerModel.toggling(etty.id, in: [etty.id], rows: listed).isEmpty)
    }

    @Test("select-all skips a blocked child, and toggles back off")
    func selectAllSkipsBlocked() {
        let naomi = candidate("Naomi", "Levin", status: .transferred, departedOn: nil)
        let etty = candidate("Etty", "Dechter")
        let listed = rows([naomi, etty], formerStudents: .shownBlocked)

        #expect(StudentPickerModel.selectableIDs(listed) == [etty.id])
        let selected = StudentPickerModel.selectAll(listed, in: [])
        #expect(selected == [etty.id])
        #expect(StudentPickerModel.selectAll(listed, in: selected).isEmpty)
    }

    @Test("the record travels onto the row it belongs to")
    func recordsLandOnRows() throws {
        let etty = candidate("Etty", "Dechter")
        let given = PresentationRecordIndex.Given(days: [try day("2026-03-11")])
        let listed = rows([etty, candidate("Naomi", "Levin")], records: [etty.id: given])

        #expect(listed.first { $0.id == etty.id }?.record == given)
        #expect(listed.first { $0.candidate.firstName == "Naomi" }?.record == nil)
    }

    // MARK: - The chip

    @Test("the chip drops the year this year, keeps it for an earlier one, and counts repeats")
    func captionWording() throws {
        // May: March is this school year (the year is judged by school year
        // since the 2026-10-12 hunt, #51), March 2025 an earlier one.
        let now = try day("2026-05-11")
        let thisYear = try day("2026-03-11")
        let lastYear = try day("2025-03-11")

        #expect(StudentRecordCaption.text(for: PresentationRecordIndex.Given(), now: now)
            == "had this before")
        #expect(StudentRecordCaption.text(for: .init(days: [thisYear]), now: now)
            == "had this \(DateFormatters.shortMonthDay.string(from: thisYear))")
        #expect(StudentRecordCaption.text(for: .init(days: [lastYear]), now: now)
            == "had this \(DateFormatters.mediumDate.string(from: lastYear))")
        #expect(StudentRecordCaption.text(for: .init(days: [lastYear, thisYear]), now: now)
            == "had this \(DateFormatters.shortMonthDay.string(from: thisYear)) ×2")
        #expect(StudentRecordCaption.accessibilityText(for: .init(days: [lastYear, thisYear]), now: now)
            == "had this \(DateFormatters.shortMonthDay.string(from: thisYear)), 2 times")
    }
}

// MARK: - Present a lesson: Selected, Ready, Everyone Else

extension StudentPickerModelTests {
    private func arranged(
        _ candidates: [StudentPickerCandidate],
        pinned: Set<UUID> = [],
        ready: Set<UUID> = [],
        search: String = "",
        sort: StudentPickerModel.Sort = .age
    ) -> [StudentPickerRow] {
        StudentPickerModel.rows(
            candidates: candidates,
            query: StudentPickerModel.Query(
                search: search,
                sort: sort,
                formerStudents: .shownIfSelected,
                arrangement: .selectedThenReady,
                pinned: pinned,
                ready: ready
            ),
            records: [:]
        )
    }

    @Test("the present-a-lesson picker runs Selected, then Ready, then everyone else, each A to Z")
    func selectedThenReadyOrder() throws {
        let zev = candidate("Zev", "Adler", birthday: try day("2015-01-01"))
        let ada = candidate("Ada", "Bell", birthday: try day("2018-01-01"))
        let mia = candidate("Mia", "Cole")
        let ben = candidate("Ben", "Dunn")
        let cyrus = candidate("Cyrus", "Eng", birthday: try day("2016-01-01"))
        let eve = candidate("Eve", "Ford")
        let people = [zev, ada, mia, ben, cyrus, eve]

        // The Age sort is ignored here: Zev is oldest, Ada youngest.
        let listed = arranged(people, pinned: [zev.id, mia.id], ready: [ben.id, ada.id])

        #expect(listed.map(\.candidate.firstName) == ["Mia", "Zev", "Ada", "Ben", "Cyrus", "Eve"])
        let placements: [StudentPickerModel.Placement?] = [
            .selected, .selected, .ready, .ready, .everyoneElse, .everyoneElse
        ]
        #expect(listed.map(\.placement) == placements)
        let readyNames: [String] = listed.filter(\.isReady).map(\.candidate.firstName)
        #expect(readyNames == ["Ada", "Ben"])

        let sections = StudentPickerModel.sections(listed)
        let runs: [StudentPickerModel.Placement?] = [.selected, .ready, .everyoneElse]
        #expect(sections.map(\.placement) == runs)
        let counts: [Int] = sections.map { $0.rows.count }
        #expect(counts == [2, 2, 2])
        let titles: [String] = sections.compactMap(\.placement).map(\.title)
        #expect(titles == ["Selected", "Ready", "Everyone Else"])
    }

    @Test("a child already picked is Selected, not Ready; an empty run gets no header")
    func selectedWinsOverReady() {
        let ada = candidate("Ada", "Bell")
        let ben = candidate("Ben", "Cole")

        let listed = arranged([ada, ben], pinned: [ada.id], ready: [ada.id])

        #expect(listed.map(\.placement) == [.selected, .everyoneElse])
        #expect(listed.first?.isReady == false)
        #expect(StudentPickerModel.sections(listed).map(\.placement) == [.selected, .everyoneElse])
    }

    @Test("same short name: A to Z by the shown name, then the full name")
    func displayNameOrderBreaksTies() {
        let sarahK = candidate("Sarah", "Klein")
        let sarahKa = candidate("Sarah", "Kahn")
        let sam = candidate("Sam", "Zur")

        #expect(arranged([sarahK, sam, sarahKa]).map(\.candidate.lastName) == ["Zur", "Kahn", "Klein"])
    }

    @Test("a child who has left is listed only when already picked, under Selected, and never Ready")
    func formerStudentOnlyWhenSelected() throws {
        let naomi = candidate("Naomi", "Levin", status: .withdrawn, departedOn: try day("2026-06-12"))
        let rivka = candidate("Rivka", "Stein", status: .transferred)
        let etty = candidate("Etty", "Dechter")

        let listed = arranged([naomi, rivka, etty], pinned: [naomi.id], ready: [rivka.id, etty.id])

        #expect(listed.map(\.candidate.firstName) == ["Naomi", "Etty"])
        let first = try #require(listed.first)
        #expect(first.placement == .selected)
        #expect(!first.isSelectable)
        // She can still be taken off, but never put back.
        #expect(StudentPickerModel.toggling(naomi.id, in: [naomi.id], rows: listed).isEmpty)
        #expect(StudentPickerModel.toggling(naomi.id, in: [], rows: listed).isEmpty)
        #expect(listed.last?.placement == .ready)

        // Unticked, she stays listed while the picker is open: the runs come
        // from who was picked when it opened, not from the live selection.
        #expect(arranged([naomi, etty], pinned: [naomi.id]).map(\.candidate.firstName) == ["Naomi", "Etty"])
        #expect(arranged([naomi, etty]).map(\.candidate.firstName) == ["Etty"])
    }

    @Test("search narrows each run and keeps the order")
    func searchInsideRuns() {
        let ada = candidate("Ada", "Bell")
        let adam = candidate("Adam", "Cole")
        let ben = candidate("Ben", "Dunn")

        let listed = arranged([ben, adam, ada], pinned: [adam.id], ready: [ada.id], search: "ad")

        #expect(listed.map(\.candidate.firstName) == ["Adam", "Ada"])
        #expect(listed.map(\.placement) == [.selected, .ready])
    }

    @Test("a sort-menu picker has no runs and keeps its sort")
    func sortMenuHasNoRuns() throws {
        let older = candidate("Zev", "Adler", birthday: try day("2015-01-01"))
        let younger = candidate("Ada", "Bell", birthday: try day("2018-01-01"))

        let listed = rows([younger, older], sort: .age)

        #expect(listed.map(\.candidate.firstName) == ["Zev", "Ada"])
        #expect(listed.allSatisfy { $0.placement == nil && !$0.isReady })
        let sections = StudentPickerModel.sections(listed)
        #expect(sections.count == 1)
        #expect(sections.first?.placement == nil)
        #expect(sections.first?.rows.count == 2)
        #expect(StudentPickerModel.sections([]).isEmpty)
    }

    // MARK: - Levels on offer

    @Test("a level is offered only when an enrolled child is at it")
    func offeredLevelsFollowEnrolledChildren() {
        let people = [
            candidate("Ada", "Bell", level: .adolescent),
            candidate("Ben", "Cole", level: .upper),
            candidate("Cy", "Dunn", level: .lower, status: .withdrawn),
            candidate("Dee", "Eng", level: .upper)
        ]

        #expect(StudentPickerModel.offeredLevels(people) == [.upper, .adolescent])
        #expect(StudentPickerModel.offeredLevels(people + [candidate("Eve", "Ford", level: .lower)])
            == [.lower, .upper, .adolescent])
        #expect(StudentPickerModel.offeredLevels([]).isEmpty)
    }
}
