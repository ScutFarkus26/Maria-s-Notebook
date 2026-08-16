import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@MainActor
struct RolloverServiceTests {

    // MARK: - Fixtures

    private func boundaryDate(year: Int, month: Int, day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - Promotion ladder

    @Test("Suggested promotion targets follow the level ladder")
    func suggestedTargets() {
        #expect(CDStudent.Level.lower.suggestedPromotionTarget == .upper)
        #expect(CDStudent.Level.upper.suggestedPromotionTarget == .adolescent)
        #expect(CDStudent.Level.adolescent.suggestedPromotionTarget == nil)
    }

    // MARK: - Apply semantics

    @Test("Promote sets level, previous level, and promotion date; the student stays enrolled")
    func promoteSemantics() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Baila", lastName: "G", level: .upper)
        CoreDataTestHelpers.save(ctx)

        let effective = try boundaryDate(year: 2026, month: 8, day: 31)
        var plan = RolloverPlan(effectiveDate: effective, writeNotes: false)
        plan.outcomes[try #require(student.id)] = .promote(to: .adolescent)

        let changed = RolloverService.apply(
            plan, students: [student], incomingYearLabel: "2026–2027", context: ctx
        )
        #expect(changed == 1)
        #expect(student.level == .adolescent)
        #expect(student.previousLevel == .upper)
        #expect(student.dateLastPromoted == effective)
        #expect(student.isEnrolled)
    }

    @Test("Transfer leaves the active roster but stays in the outgoing year's lens")
    func transferSemantics() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(
            in: ctx, firstName: "Leora", lastName: "B", level: .lower,
            dateStarted: try boundaryDate(year: 2025, month: 8, day: 24)
        )
        CoreDataTestHelpers.save(ctx)

        let effective = try boundaryDate(year: 2026, month: 8, day: 31)
        var plan = RolloverPlan(effectiveDate: effective, writeNotes: false)
        plan.outcomes[try #require(student.id)] = .transfer
        RolloverService.apply(plan, students: [student], incomingYearLabel: "2026–2027", context: ctx)

        #expect(student.isTransferred)
        #expect(!student.isEnrolled)
        #expect(student.dateWithdrawn == effective)

        // Excluded by the canonical active-roster predicate.
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        #expect(try ctx.fetch(request).isEmpty)

        // Year lens: visible in the outgoing year, gone from the incoming one.
        let outgoing = DateRange(
            start: try boundaryDate(year: 2025, month: 9, day: 1),
            end: try boundaryDate(year: 2026, month: 9, day: 1)
        )
        let incoming = DateRange(
            start: try boundaryDate(year: 2026, month: 9, day: 1),
            end: try boundaryDate(year: 2027, month: 9, day: 1)
        )
        #expect(student.isActive(in: outgoing))
        #expect(!student.isActive(in: incoming))
    }

    @Test("Withdraw mirrors transfer but keeps the distinct status")
    func withdrawSemantics() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ashira", lastName: "B", level: .upper)
        CoreDataTestHelpers.save(ctx)

        let effective = try boundaryDate(year: 2026, month: 8, day: 31)
        var plan = RolloverPlan(effectiveDate: effective, writeNotes: false)
        plan.outcomes[try #require(student.id)] = .withdraw
        RolloverService.apply(plan, students: [student], incomingYearLabel: "2026–2027", context: ctx)

        #expect(student.isWithdrawn)
        #expect(!student.isTransferred)
        #expect(student.dateWithdrawn == effective)
    }

    @Test("Stay is a no-op: nothing changes and modifiedAt is untouched")
    func staySemantics() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Etty", lastName: "D", level: .upper)
        CoreDataTestHelpers.save(ctx)
        let modifiedBefore = student.modifiedAt

        let plan = RolloverPlan(effectiveDate: Date(), writeNotes: true)
        let changed = RolloverService.apply(
            plan, students: [student], incomingYearLabel: "2026–2027", context: ctx
        )

        #expect(changed == 0)
        #expect(student.isEnrolled)
        #expect(student.level == .upper)
        #expect(student.modifiedAt == modifiedBefore)
        let notes = try ctx.fetch(CDFetchRequest(CDNote.self))
        #expect(notes.isEmpty)
    }

    // MARK: - Notes

    @Test("Rollover logs one student-scoped, report-flagged observation per change")
    func rolloverNotes() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let promoted = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Brielle", lastName: "F", level: .upper)
        let transferred = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Gloria", lastName: "J", level: .lower)
        CoreDataTestHelpers.save(ctx)

        let effective = try boundaryDate(year: 2026, month: 8, day: 31)
        var plan = RolloverPlan(effectiveDate: effective, writeNotes: true)
        plan.outcomes[try #require(promoted.id)] = .promote(to: .adolescent)
        plan.outcomes[try #require(transferred.id)] = .transfer
        RolloverService.apply(plan, students: [promoted, transferred], incomingYearLabel: "2026–2027", context: ctx)

        let notes = try ctx.fetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.includeInReport })
        #expect(notes.allSatisfy { $0.createdAt == effective })

        let promotedID = try #require(promoted.id)
        let promotionNote = try #require(notes.first { $0.scope.applies(to: promotedID) })
        #expect(promotionNote.body.contains("Promoted from Upper to Adolescent"))
        #expect(promotionNote.body.contains("2026–2027"))

        let transferredID = try #require(transferred.id)
        let transferNote = try #require(notes.first { $0.scope.applies(to: transferredID) })
        #expect(transferNote.body.contains("Transferred"))
    }

    // MARK: - Summary

    @Test("Summary counts every outcome bucket")
    func summaryCounts() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let one = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "A", lastName: "1", level: .lower)
        let two = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "B", lastName: "2", level: .upper)
        let three = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "C", lastName: "3", level: .lower)
        let four = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "D", lastName: "4", level: .upper)
        CoreDataTestHelpers.save(ctx)

        var plan = RolloverPlan()
        plan.outcomes[try #require(one.id)] = .promote(to: .upper)
        plan.outcomes[try #require(two.id)] = .promote(to: .adolescent)
        plan.outcomes[try #require(three.id)] = .transfer
        // four stays (no entry).

        let summary = RolloverService.summary(for: plan, students: [one, two, three, four])
        #expect(summary.promoted[.upper] == 1)
        #expect(summary.promoted[.adolescent] == 1)
        #expect(summary.transferred == 1)
        #expect(summary.withdrawn == 0)
        #expect(summary.staying == 1)
        #expect(summary.changeCount == 3)
        #expect(summary.text.contains("1 promoted to Adolescent"))
    }
}

// MARK: - Roster filtering regression

@MainActor
struct FormerStudentRosterTests {

    @Test("Transferred students leave the active roster and join the former-students bucket")
    func transferredStudentsAreFormer() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Active", lastName: "One", level: .upper)
        CoreDataTestHelpers.seedStudent(
            in: ctx, firstName: "Trans", lastName: "Ferred", level: .lower,
            enrollmentStatus: .transferred, dateWithdrawn: Date()
        )
        CoreDataTestHelpers.seedStudent(
            in: ctx, firstName: "With", lastName: "Drawn", level: .lower,
            enrollmentStatus: .withdrawn, dateWithdrawn: Date()
        )
        CoreDataTestHelpers.save(ctx)

        let viewModel = StudentsViewModel()
        let active = viewModel.filteredStudents(viewContext: ctx, filter: .all, sortOrder: .alphabetical)
        #expect(active.map(\.firstName) == ["Active"])

        let former = viewModel.filteredStudents(viewContext: ctx, filter: .withdrawn, sortOrder: .alphabetical)
        #expect(Set(former.map(\.firstName)) == ["Trans", "With"])
    }

    @Test("The adolescent roster filter matches only adolescent students")
    func adolescentFilter() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Sarah", lastName: "M", level: .adolescent)
        CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Naomi", lastName: "L", level: .upper)
        CoreDataTestHelpers.save(ctx)

        let viewModel = StudentsViewModel()
        let adolescents = viewModel.filteredStudents(viewContext: ctx, filter: .adolescent, sortOrder: .alphabetical)
        #expect(adolescents.map(\.firstName) == ["Sarah"])
    }

    @Test("The Today level filter matches the adolescent level")
    func levelFilterMatches() {
        #expect(LevelFilter.adolescent.matches(.adolescent))
        #expect(!LevelFilter.adolescent.matches(.upper))
        #expect(LevelFilter.all.matches(.adolescent))
    }

    @Test("CSV level parsing accepts adolescent synonyms")
    func parseLevelAdolescent() {
        #expect(StudentCSVImporter.parseLevel(from: "Adolescent") == .adolescent)
        #expect(StudentCSVImporter.parseLevel(from: "adol") == .adolescent)
        #expect(StudentCSVImporter.parseLevel(from: "12-15") == .adolescent)
        #expect(StudentCSVImporter.parseLevel(from: "Erdkinder") == .adolescent)
        #expect(StudentCSVImporter.parseLevel(from: "lower el") == .lower)
        #expect(StudentCSVImporter.parseLevel(from: "nonsense") == nil)
    }
}
