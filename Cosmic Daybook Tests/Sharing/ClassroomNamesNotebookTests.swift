import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The notebook's side of the names people set for themselves: the lead
// guide's "Your name" in Settings › Classroom writes his row, and the screens
// that name people (Restock's who-lines, the roll's marks, the front-desk
// email, list_supplies over MCP) read the list from the store, so a person's
// current name beats the one stamped, and with no row the stamped name stays.
@Suite("Classroom names: the notebook", .serialized)
@MainActor
struct ClassroomNamesNotebookTests {

    private typealias Support = ClassroomNamesTestSupport

    /// Ana named herself "Ana B" after stamping her first changes "Ana"; Cal
    /// never named himself in the list.
    private func seedList(in context: NSManagedObjectContext) throws -> ClassroomNames.Snapshot {
        Support.person("_guide", "Danny", role: .leadGuide, created: Support.at(0), in: context)
        Support.person("_ana", "Ana B", role: .assistant, created: Support.at(10), in: context)
        #expect(CoreDataTestHelpers.save(context))
        return ClassroomNames.snapshot(in: context)
    }

    // MARK: - Settings › Classroom › Your name

    @Test("Your name saves the guide's row; a rename changes that row, and clearing keeps it empty")
    func yourNameWritesTheGuidesRow() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try await Support.asDevice(recordName: "_guide") {
            #expect(await ClassroomYourNameCard.setName("Danny", in: context, save: CoreDataTestHelpers.save))
            #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "Danny")
            #expect(ClassroomNames.guideName(in: context) == "Danny")

            #expect(await ClassroomYourNameCard.setName("Dan", in: context, save: CoreDataTestHelpers.save))
            let rows = context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
            #expect(rows.count == 1)
            let row = try #require(rows.first)
            #expect(row.recordName == "_guide")
            #expect(row.role == .leadGuide)
            #expect(row.displayName == "Dan")
            #expect(!context.hasChanges, "saved, not left pending on the view context")

            #expect(await ClassroomYourNameCard.setName("", in: context, save: CoreDataTestHelpers.save))
            #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).map(\.displayName) == [""])
            #expect(ClassroomNames.guideName(in: context) == nil)
            #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "")
        }
    }

    @Test("Before the guide's record name is known, his name waits on the device")
    func yourNameWaitsForTheRecordName() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        await Support.asDevice(recordName: nil) {
            #expect(await ClassroomYourNameCard.setName("Danny", in: context, save: CoreDataTestHelpers.save))
            #expect(ClassroomIdentity.nameWaitingAs == .leadGuide)
            #expect(ClassroomIdentity.displayName == "Danny")
            #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "Danny")
            #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).isEmpty)
        }
    }

    @Test("Search finds Your name in the Classroom pane")
    func searchFindsYourName() {
        #expect(SettingsCategory.classroom.matches("your name"))
    }

    // MARK: - Restock

    @Test("Restock's who-lines on the guide's devices use her current name, else the stamped one")
    func restockWhoLines() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let names = try seedList(in: context)
        let guide = RestockAuthor(role: .leadGuide, recordName: "_guide").reading(names)

        #expect(RestockView.addedByLine(changedByID: "_ana", name: "Ana", viewer: guide) == "added by Ana B")
        #expect(RestockView.addedByLine(changedByID: "_cal", name: "Cal", viewer: guide) == "added by Cal")
        #expect(RestockView.addedByLine(changedByID: "_guide", name: "", viewer: guide) == nil)

        let now = Date()
        let hers = RestockView.byLine(
            isNeeded: true, changedAt: now, changedByID: "_ana", name: "Ana", viewer: guide, now: now
        )
        #expect(hers.hasPrefix("Ana B · "))
        let his = RestockView.byLine(
            isNeeded: true, changedAt: now, changedByID: "_cal", name: "Cal", viewer: guide, now: now
        )
        #expect(his.hasPrefix("Cal · "))

        // Without the list, her old stamp reads as stamped.
        let withoutList = RestockAuthor(role: .leadGuide, recordName: "_guide")
        #expect(RestockView.addedByLine(changedByID: "_ana", name: "Ana", viewer: withoutList) == "added by Ana")
    }

    // MARK: - Attendance

    @Test("The roll and the front-desk line on the guide's devices use her current name, else the stamped one")
    func attendanceNames() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let names = try seedList(in: context)

        // As `AttendanceGrid.markedBy` asks on the guide's devices.
        func markedBy(_ row: AttendanceRow) -> String? {
            AttendanceRules.markerName(
                for: row, myRecordName: "_guide", myName: nil, guideName: "you", names: names
            )
        }
        #expect(markedBy(Support.mark(by: .assistant, id: "_ana", name: "Ana", in: context)) == "Ana B")
        #expect(markedBy(Support.mark(by: .assistant, id: "_cal", name: "Cal", in: context)) == "Cal")
        #expect(markedBy(Support.mark(by: .leadGuide, id: "_guide", name: nil, in: context)) == "you")

        // As `AttendanceExpandedView.frontDeskSummary` asks.
        func sender(_ send: AttendanceEmailLog.Send) -> String {
            send.senderName(viewerRole: .leadGuide, myRecordName: "_guide", myName: nil, names: names)
        }
        #expect(sender(Support.send(by: .assistant, id: "_ana", name: "Ana", in: context)) == "Ana B")
        #expect(sender(Support.send(by: .assistant, id: "_cal", name: "Cal", in: context)) == "Cal")
        #expect(sender(Support.send(by: .leadGuide, id: "_guide", name: nil, in: context)) == "you")
    }

    // MARK: - MCP

    @Test("list_supplies says who set a level by the name they go by now")
    func listSuppliesUsesCurrentNames() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let listSupplies = try #require(tools.first { $0.name == "list_supplies" })

        for (name, id, stamped) in [("Paper Towels", "_ana", "Ana"), ("Tissues", "_cal", "Cal")] {
            let supply = CDSupply(context: context)
            supply.id = UUID()
            supply.name = name
            supply.createdAt = Support.at(0)
            supply.levelChangedAt = Support.at(100)
            supply.levelChangedByID = id
            supply.levelChangedByName = stamped
        }
        _ = try seedList(in: context)

        let lines = try await listSupplies.handler([:]).components(separatedBy: "\n")
        let towels = try #require(lines.first { $0.contains("Paper Towels") })
        let tissues = try #require(lines.first { $0.contains("Tissues") })
        #expect(towels.contains("by Ana B"))
        #expect(tissues.contains("by Cal"))
    }
}
