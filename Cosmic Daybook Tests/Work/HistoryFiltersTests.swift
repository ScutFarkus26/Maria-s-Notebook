import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The two Histories in Lessons & Work (plan "Simplify the app", Phase 2):
/// Work History keeps the old Logs screen's status menu, limited to the
/// finished statuses, and both Histories' search reads the children's names
/// as the live lists do.
@Suite("Lessons & Work History: status menu and name search")
@MainActor
struct HistoryFiltersTests {

    // MARK: - Status menu

    @Test("History offers only the finished statuses; the full log offers all of them")
    func statusChoices() {
        let history = WorksLogRows.statusChoices(completedOnly: true)
        #expect(!history.isEmpty)
        #expect(history.allSatisfy { $0.isClosed })
        #expect(Set(history) == Set(WorkStatus.allCases.filter(\.isClosed)))
        #expect(WorksLogRows.statusChoices(completedOnly: false) == Array(WorkStatus.allCases))
    }

    @Test("A picked status keeps only its rows, and none picked keeps every row")
    func statusFilter() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let mastered = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead chain")
        mastered.status = .mastered
        let finished = CoreDataTestHelpers.seedWorkModel(in: context, title: "Map puzzle")
        finished.status = .done

        #expect(WorksLogRows.matches(mastered, statuses: []))
        #expect(WorksLogRows.matches(mastered, statuses: [.mastered]))
        #expect(!WorksLogRows.matches(finished, statuses: [.mastered]))
        #expect(WorksLogRows.matches(finished, statuses: [.mastered, .done]))
    }

    // MARK: - Name search

    @Test("The search reads a title, or any spelling of a child's name, in any case")
    func searchMatching() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let texts = ["Checkerboard"] + HistorySearch.names(of: maya)

        #expect(HistorySearch.matches("checker", in: texts))
        #expect(HistorySearch.matches("MAYA", in: texts))
        #expect(HistorySearch.matches("stone", in: texts))
        #expect(HistorySearch.matches("maya s", in: texts), "the short form")
        #expect(HistorySearch.matches("maya stone", in: texts), "the full name")
        #expect(!HistorySearch.matches("eli", in: texts))
        #expect(HistorySearch.matches("  ", in: ["Checkerboard"]), "an empty search keeps every row")
    }

    @Test("A work row is searched by its owner, not by classmates its linked copies name")
    func workSearchedByOwner() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let mayaID = try #require(maya.id)
        let eliID = try #require(eli.id)

        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead chain", studentID: mayaID)
        let onBoth = CDWorkParticipantEntity(context: context)
        onBoth.studentID = eliID.uuidString
        onBoth.work = work
        #expect(HistorySearch.searchedStudentIDs(of: work) == [mayaID])

        // Offered project work has no owner until a child claims it.
        let offered = CoreDataTestHelpers.seedWorkModel(in: context, title: "Group project")
        offered.studentID = ""
        let claimant = CDWorkParticipantEntity(context: context)
        claimant.studentID = eliID.uuidString
        claimant.work = offered
        #expect(HistorySearch.searchedStudentIDs(of: offered) == [eliID])
    }

    // MARK: - Attendance route

    @Test("A route that needs the roll saves it over a saved List")
    func showRollOverridesList() throws {
        let defaults = try #require(UserDefaults(suiteName: "HistoryFiltersTests-\(UUID().uuidString)"))
        defaults.set(AttendanceScreenView.list.rawValue, forKey: UserDefaultsKeys.attendanceScreenView)
        AttendanceScreenView.showRoll(defaults: defaults)
        let saved = defaults.string(forKey: UserDefaultsKeys.attendanceScreenView)
        #expect(AttendanceScreenView.resolved(rawValue: saved) == .roll)
    }
}
