import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bug hunt 2026-10-20, Siri: sound-alike names on the grid
// and in Siri's answers (#26), refusals that named a child in full on a
// locked phone (#29), "We're out of…" on a staple whose need had gone (#28),
// and "Add glue sticks." keeping its period (#32).
@Suite("Assistant Siri (Fix1020 SR)")
@MainActor
struct AssistantSiriFix1020SRTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    // MARK: - #26 Sound-alike names

    @Test("Sound-alike first names get an initial on the grid, as shared ones do")
    func soundAlikeGridNames() {
        let saraK = AssistantTestSupport.student("Sara", "Klein", in: context)
        let sarahA = AssistantTestSupport.student("Sarah", "Adler", in: context)
        let noa = AssistantTestSupport.student("Noa", "Levi", in: context)
        let noah = AssistantTestSupport.student("Noah", "Gold", in: context)
        let bet = AssistantTestSupport.student("Bet", "Ross", in: context)
        let beth = AssistantTestSupport.student("Beth", "Cole", in: context)
        // Sound-alike short forms too: the full name tells them apart.
        let rivka = AssistantTestSupport.student("Rivka", "Stone", in: context)
        let rivkah = AssistantTestSupport.student("Rivkah", "Shaw", in: context)

        let names = AttendanceGridNames.names(for: [saraK, sarahA, noa, noah, bet, beth, rivka, rivkah])

        #expect(names[saraK.objectID] == "Sara K")
        #expect(names[sarahA.objectID] == "Sarah A")
        #expect(names[noa.objectID] == "Noa L")
        #expect(names[noah.objectID] == "Noah G")
        #expect(names[bet.objectID] == "Bet")
        #expect(names[beth.objectID] == "Beth")
        #expect(names[rivka.objectID] == "Rivka Stone")
        #expect(names[rivkah.objectID] == "Rivkah Shaw")
    }

    // MARK: - #29 Refusals

    private func siri(on day: Date) -> SiriAttendance {
        SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
    }

    /// The error as written, case and name: `notStarted("Noa L")`.
    nonisolated private static func described(_ error: any Error) -> String {
        String(describing: error)
    }

    @Test("A child who has left is not found, by her grid name, never refused by her full name")
    func formerChildIsNotFound() throws {
        let day = try AssistantTestSupport.day("2031-01-07")
        let leah = AssistantTestSupport.student("Leah", "Hart", in: context)
        leah.enrollmentStatusRaw = CDStudent.EnrollmentStatus.withdrawn.rawValue
        leah.dateWithdrawn = day.addingTimeInterval(-7 * 86_400)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())

        let entity = try #require(StudentEntity(student: leah))
        #expect { try siri(on: day).student(for: entity) } throws: {
            Self.described($0) == #"studentNotFound("Leah")"#
        }
    }

    @Test("A child who hasn't started is refused by her grid name")
    func notStartedUsesGridName() throws {
        let day = try AssistantTestSupport.day("2031-01-07")
        let noa = AssistantTestSupport.student("Noa", "Levi", in: context)
        noa.dateStarted = day.addingTimeInterval(7 * 86_400)
        AssistantTestSupport.student("Noah", "Gold", in: context)
        #expect(context.safeSave())

        let entity = try #require(StudentEntity(student: noa))
        #expect { try siri(on: day).student(for: entity) } throws: {
            Self.described($0) == #"notStarted("Noa L")"#
        }
    }

    // MARK: - #28 and #32 Restock by Siri

    private static let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
    private static let ana = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")

    private var restock: AssistantSiriRestock { AssistantSiriRestock(stack: stack, author: Self.ana) }

    @Test("We're out of… on an Out staple whose need went opens it again and says marked")
    func outReopensLostNeed() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", level: .out, in: context)
        let id = try #require(towels.id)
        // Another device closed the need as this one marked it Out.
        for need in RestockService.openNeeds(for: towels, in: context) { context.delete(need) }
        #expect(context.safeSave())

        #expect(try restock.mark(id, as: .out) == .marked("Paper Towels", .out, .office))
        #expect(RestockService.openNeeds(for: towels, in: context).count == 1)
        #expect(!context.hasChanges)
        // With its need in place, the same command changes nothing.
        #expect(try restock.mark(id, as: .out) == .already("Paper Towels", .out))
    }

    @Test("We're low on… an Out staple whose need went opens it again, still Out")
    func lowOnOutReopensLostNeed() throws {
        let paper = try AssistantRestockTestSupport.staple("Toilet Paper", level: .out, in: context)
        let id = try #require(paper.id)
        for need in RestockService.openNeeds(for: paper, in: context) { context.delete(need) }
        #expect(context.safeSave())

        #expect(try restock.mark(id, as: .low) == .marked("Toilet Paper", .out, .office))
        #expect(paper.level == .out)
        #expect(RestockService.openNeeds(for: paper, in: context).count == 1)
    }

    @Test("Add to the office run drops the period Siri wrote, so it's one need, not two")
    func officeRunDropsEndingPunctuation() throws {
        #expect(try restock.addToOfficeRun("Glue sticks.") == .added("Glue sticks"))
        #expect(try restock.addToOfficeRun("Glue sticks") == .alreadyListed("Glue sticks"))
        #expect(RestockService.openNeeds(in: context).count == 1)
    }
}
