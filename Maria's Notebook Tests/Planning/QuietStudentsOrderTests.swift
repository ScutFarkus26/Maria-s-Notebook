import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The quiet list decides who the guide sees on the Work half, and the two
/// things it can get wrong both make a child disappear: reading only a work
/// item's `studentID` hides everyone in group work, and rolling up the wrong end
/// of a child's work makes a child who was checked yesterday look neglected.
@Suite("Quiet students order")
@MainActor
struct QuietStudentsOrderTests {

    private func makeStudent(
        _ context: NSManagedObjectContext,
        first: String,
        last: String
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        return student
    }

    @discardableResult
    private func makeWork(
        _ context: NSManagedObjectContext,
        owner: CDStudent? = nil,
        participants: [(CDStudent, completed: Bool)] = []
    ) -> CDWorkModel {
        let work = CDWorkModel(context: context)
        work.id = UUID()
        work.status = .active
        work.studentID = owner?.id?.uuidString ?? ""
        for (student, completed) in participants {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = student.id?.uuidString ?? ""
            participant.completedAt = completed ? Date() : nil
            work.addToParticipants(participant)
        }
        return work
    }

    // MARK: - Whose work an item is

    @Test("Work with no participant rows belongs to the child named on it")
    func soloWorkNamesItsOwner() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let work = makeWork(context, owner: ada)

        #expect(QuietStudentsOrder.openStudentIDs(of: work) == Set([ada.id!]))
    }

    @Test("Group work counts every participant, not just the child named on it")
    func groupWorkCountsParticipants() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        // The trap this exists to catch: reading `studentID` alone reports the
        // other four children as having nothing open, which is the one case the
        // column is for.
        let ada = makeStudent(context, first: "Ada", last: "One")
        let bram = makeStudent(context, first: "Bram", last: "Two")
        let cleo = makeStudent(context, first: "Cleo", last: "Three")
        let work = makeWork(
            context,
            owner: ada,
            participants: [(ada, completed: false), (bram, completed: false), (cleo, completed: false)]
        )

        #expect(QuietStudentsOrder.openStudentIDs(of: work) == Set([ada.id!, bram.id!, cleo.id!]))
    }

    @Test("A participant who has finished their part is no longer carrying it")
    func completedParticipantsDropOut() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "One")
        let bram = makeStudent(context, first: "Bram", last: "Two")
        let work = makeWork(
            context,
            owner: ada,
            participants: [(ada, completed: false), (bram, completed: true)]
        )

        // The item is still open — for Ada.
        #expect(QuietStudentsOrder.openStudentIDs(of: work) == Set([ada.id!]))
    }

    @Test("An owner with no participant row of their own still counts")
    func ownerWithoutAParticipantRowCounts() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "One")
        let bram = makeStudent(context, first: "Bram", last: "Two")
        let work = makeWork(context, owner: ada, participants: [(bram, completed: false)])

        #expect(QuietStudentsOrder.openStudentIDs(of: work) == Set([ada.id!, bram.id!]))
    }

    @Test("An owner whose own participant row is complete does not count")
    func completedOwnerDoesNotCount() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "One")
        let bram = makeStudent(context, first: "Bram", last: "Two")
        let work = makeWork(
            context,
            owner: ada,
            participants: [(ada, completed: true), (bram, completed: false)]
        )

        #expect(QuietStudentsOrder.openStudentIDs(of: work) == Set([bram.id!]))
    }

    // MARK: - The rollup

    @Test("A child's number is their most recently touched work, not their oldest")
    func rollupTakesTheMostRecentTouch() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let stale = makeWork(context, owner: ada)
        let fresh = makeWork(context, owner: ada)

        let ages: [UUID: Int] = [stale.id!: 40, fresh.id!: 2]
        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: [stale, fresh]) {
            $0.id.flatMap { ages[$0] } ?? 0
        }

        // The 40-day item is what the card's own bar is for. This list is asking
        // how long the *child* went unattended, and that was two days.
        #expect(rollup[ada.id!] == 2)
    }

    @Test("Every participant in a group item gets its number")
    func rollupReachesParticipants() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "One")
        let bram = makeStudent(context, first: "Bram", last: "Two")
        let work = makeWork(
            context,
            owner: ada,
            participants: [(ada, completed: false), (bram, completed: false)]
        )

        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: [work]) { _ in 7 }

        #expect(rollup[ada.id!] == 7)
        #expect(rollup[bram.id!] == 7)
    }

    @Test("A child with no open work is absent from the rollup")
    func childrenWithoutWorkAreAbsent() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let busy = makeStudent(context, first: "Ada", last: "One")
        let idle = makeStudent(context, first: "Bram", last: "Two")
        let work = makeWork(context, owner: busy)

        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: [work]) { _ in 3 }

        #expect(rollup[busy.id!] == 3)
        #expect(rollup[idle.id!] == nil)
    }

    // MARK: - The list

    @Test("A child with no open work sorts above everyone")
    func withoutWorkSortsFirst() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let idle = makeStudent(context, first: "Ada", last: "Byron")
        let quiet = makeStudent(context, first: "Bram", last: "Cole")

        let rollup = [quiet.id!: 40]
        let ordered = QuietStudentsOrder.ordered(
            students: [quiet, idle],
            daysSinceTouch: rollup,
            studentIDsWithOpenWork: Set(rollup.keys),
            scope: .everyone
        )

        #expect(ordered.map(\.student.id) == [idle.id, quiet.id])
        // Nothing to measure from, which the row reads as "No open work".
        #expect(ordered.first?.isUncounted == true)
    }

    @Test("Longest quiet comes first")
    func longestQuietFirst() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let recent = makeStudent(context, first: "Ada", last: "One")
        let middle = makeStudent(context, first: "Bram", last: "Two")
        let stale = makeStudent(context, first: "Cleo", last: "Three")

        let rollup = [recent.id!: 1, middle.id!: 9, stale.id!: 30]
        let ordered = QuietStudentsOrder.ordered(
            students: [recent, middle, stale],
            daysSinceTouch: rollup,
            studentIDsWithOpenWork: Set(rollup.keys),
            scope: .everyone
        )

        #expect(ordered.map(\.student.id) == [stale.id, middle.id, recent.id])
    }

    @Test("Without Work hides every child who is carrying something")
    func withoutWorkScopeHidesBusyChildren() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let busy = makeStudent(context, first: "Ada", last: "One")
        let idle = makeStudent(context, first: "Bram", last: "Two")

        let rollup = [busy.id!: 20]

        let everyone = QuietStudentsOrder.ordered(
            students: [busy, idle],
            daysSinceTouch: rollup,
            studentIDsWithOpenWork: Set(rollup.keys),
            scope: .everyone
        )
        #expect(everyone.count == 2)

        let withoutWork = QuietStudentsOrder.ordered(
            students: [busy, idle],
            daysSinceTouch: rollup,
            studentIDsWithOpenWork: Set(rollup.keys),
            scope: .withoutWork
        )
        #expect(withoutWork.map(\.student.id) == [idle.id])
    }

    @Test("Searching narrows the list by name")
    func searchNarrowsByName() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let bram = makeStudent(context, first: "Bram", last: "Cole")

        let rollup = [ada.id!: 10, bram.id!: 20]
        let ordered = QuietStudentsOrder.ordered(
            students: [ada, bram],
            daysSinceTouch: rollup,
            studentIDsWithOpenWork: Set(rollup.keys),
            scope: .everyone,
            search: "ada"
        )

        #expect(ordered.map(\.student.id) == [ada.id])
    }

    // MARK: - Wording

    @Test("The two columns say the same shape of thing in their own words")
    func vocabulariesStayParallel() {
        #expect(StudentWaitVocabulary.lessons.detail(forDays: nil) == "Never taught")
        #expect(StudentWaitVocabulary.work.detail(forDays: nil) == "No open work")
        #expect(StudentWaitVocabulary.lessons.detail(forDays: 0) == "Taught today")
        #expect(StudentWaitVocabulary.work.detail(forDays: 0) == "Checked today")
        // Everything past today is counted the same way on both sides.
        #expect(StudentWaitVocabulary.lessons.detail(forDays: 1) == "1 school day ago")
        #expect(StudentWaitVocabulary.work.detail(forDays: 1) == "1 school day ago")
        #expect(StudentWaitVocabulary.work.detail(forDays: 12) == "12 school days ago")
    }
}
