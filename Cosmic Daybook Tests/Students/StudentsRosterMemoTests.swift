import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The roster screen memoizes its two lists per query until a Student
/// changes, reloads only attendance on an attendance change unless the table
/// caches' own inputs moved, and reads observation dates as dictionaries.
/// These pin each against the path it replaced.
@Suite("Students roster memo")
@MainActor
struct StudentsRosterMemoTests {

    private func seedRoster(in context: NSManagedObjectContext) {
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Stone", level: .upper)
        ada.manualOrder = 2
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Hart", level: .lower)
        ben.manualOrder = 1
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy", lastName: "Lee", level: .upper)
        cy.manualOrder = 0
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Dee", lastName: "Moss", enrollmentStatus: .withdrawn
        )
    }

    private func ids(_ students: [CDStudent]) -> [NSManagedObjectID] { students.map(\.objectID) }

    @Test("Memoized lists equal the fetch for every query, and refetch only after a Student change")
    func memoMatchesFetch() throws {
        let context = try CoreDataTestHelpers.makeContext()
        seedRoster(in: context)
        #expect(CoreDataTestHelpers.save(context))
        let viewModel = StudentsViewModel()

        let queries: [(StudentsFilter, CosmicDaybook.SortOrder, String)] = [
            (.all, .alphabetical, ""), (.all, .manual, ""), (.upper, .age, ""),
            (.all, .birthday, ""), (.withdrawn, .alphabetical, ""), (.all, .alphabetical, "a")
        ]
        func check() {
            for (filter, sort, search) in queries {
                let memo = viewModel.memoizedFilteredStudents(
                    viewContext: context, filter: filter, sortOrder: sort, searchString: search
                )
                let fresh = viewModel.filteredStudents(
                    viewContext: context, filter: filter, sortOrder: sort, searchString: search
                )
                #expect(ids(memo) == ids(fresh))
            }
        }

        check()
        let fetchesAfterFirstPass = viewModel.rosterFetchCount
        #expect(fetchesAfterFirstPass == queries.count)
        check()
        #expect(viewModel.rosterFetchCount == fetchesAfterFirstPass)

        // An attendance save does not touch a Student.
        CoreDataTestHelpers.seedAttendance(in: context)
        #expect(CoreDataTestHelpers.save(context))
        check()
        #expect(viewModel.rosterFetchCount == fetchesAfterFirstPass)

        // A rename, a new child and a withdrawal all refetch.
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "firstName == %@", "Ben")
        let ben = try #require(context.safeFetch(request).first)
        ben.firstName = "Abe"
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eve", lastName: "Park", level: .upper)
        check() // unsaved: every read refetches, still equal
        #expect(CoreDataTestHelpers.save(context))
        check()
        #expect(viewModel.rosterFetchCount > fetchesAfterFirstPass)
        ben.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(context))
        check()
    }

    @Test("An attendance change reloads attendance alone unless a table input moved")
    func attendanceReloadGate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        seedRoster(in: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        #expect(CoreDataTestHelpers.save(context))
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let calendar = AppCalendar.shared
        let viewModel = StudentsViewModel()

        viewModel.loadDataOnDemand(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 1)

        let ada = try #require(students.first { $0.firstName == "Ada" })
        CoreDataTestHelpers.seedAttendance(in: context, studentID: try #require(ada.id), date: Date())
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reloadAfterAttendanceChange(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 1)
        #expect(viewModel.cachedAttendanceRecords.count == 1)

        // A next-lesson pick and an observation are table inputs.
        ada.nextLessonUUIDs = [try #require(lesson.id)]
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100")
        note.scope = .student(try #require(ada.id))
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reloadAfterAttendanceChange(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 2)

        let fresh = StudentsViewModel()
        fresh.loadDataOnDemand(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.cachedNextLessonNames == fresh.cachedNextLessonNames)
        #expect(viewModel.cachedNextLessonNames[try #require(ada.id)] == "Golden Beads")
        #expect(viewModel.cachedLastObservationDates == fresh.cachedLastObservationDates)
        #expect(viewModel.cachedDaysSinceLastLesson == fresh.cachedDaysSinceLastLesson)
    }

    @Test("Observation dates read as dictionaries equal the object path (SQLite)")
    func observationDatesDictionaryMatchesObjects() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy")
        let adaID = try #require(ada.id)
        let benID = try #require(ben.id)
        let cyID = try #require(cy.id)
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

        let direct = CoreDataTestHelpers.seedNote(in: context, body: "Direct")
        direct.scope = .student(adaID)
        direct.updatedAt = base.addingTimeInterval(100)

        let older = CoreDataTestHelpers.seedNote(in: context, body: "Older")
        older.scope = .student(adaID)
        older.updatedAt = nil
        older.createdAt = base

        let group = CoreDataTestHelpers.seedNote(in: context, body: "Group")
        group.scope = .students([benID, cyID])
        group.updatedAt = base.addingTimeInterval(200)
        for id in [benID, cyID] {
            let link = CDNoteStudentLink(context: context)
            link.studentIDUUID = id
            link.note = group
        }

        let wholeClass = CoreDataTestHelpers.seedNote(in: context, body: "Everyone")
        wholeClass.scope = .all
        wholeClass.updatedAt = base.addingTimeInterval(900)
        let classLink = CDNoteStudentLink(context: context)
        classLink.studentIDUUID = cyID
        classLink.note = wholeClass
        try context.save()

        #expect(StudentsViewModel.directNoteRows(in: context) != nil)
        #expect(StudentsViewModel.linkRows(in: context) != nil)
        let wanted: Set<UUID> = [adaID, benID]
        let dictionaryPath = StudentsViewModel.latestObservationDates(for: wanted, in: context)

        // Any unsaved change sends the read down the object path.
        CoreDataTestHelpers.seedLesson(in: context)
        #expect(context.hasChanges)
        let objectPath = StudentsViewModel.latestObservationDates(for: wanted, in: context)

        #expect(dictionaryPath == objectPath)
        #expect(dictionaryPath[adaID] == base.addingTimeInterval(100))
        #expect(dictionaryPath[benID] == base.addingTimeInterval(200))
        #expect(dictionaryPath[cyID] == nil)
    }
}
