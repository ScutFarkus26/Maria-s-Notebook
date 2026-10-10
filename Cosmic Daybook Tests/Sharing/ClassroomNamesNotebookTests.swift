import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

extension ClassroomNamesSuites {

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
                #expect(await ClassroomYourNameCard.setName("Danny", in: context, save: CoreDataTestHelpers.save) == .saved)
                #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "Danny")
                #expect(ClassroomNames.guideName(in: context) == "Danny")

                #expect(await ClassroomYourNameCard.setName("Dan", in: context, save: CoreDataTestHelpers.save) == .saved)
                let rows = context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
                #expect(rows.count == 1)
                let row = try #require(rows.first)
                #expect(row.recordName == "_guide")
                #expect(row.role == .leadGuide)
                #expect(row.displayName == "Dan")
                #expect(!context.hasChanges, "saved, not left pending on the view context")

                #expect(await ClassroomYourNameCard.setName("", in: context, save: CoreDataTestHelpers.save) == .saved)
                #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).map(\.displayName) == [""])
                #expect(ClassroomNames.guideName(in: context) == nil)
                #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "")
            }
        }

        @Test("Before the guide's record name is known, his name waits on the device")
        func yourNameWaitsForTheRecordName() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            await Support.asDevice(recordName: nil) {
                let saved = await ClassroomYourNameCard.setName("Danny", in: context, save: CoreDataTestHelpers.save)
                #expect(saved == .waiting)
                #expect(ClassroomIdentity.nameWaitingAs == .leadGuide)
                #expect(ClassroomIdentity.displayName == "Danny")
                #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "Danny")
                #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).isEmpty)
            }
        }

        // Bug hunt 2026-10-09, #5: an account change during the save took the
        // name back, and the card still showed it as saved.
        @Test("Another Apple Account signing in while his name saves reads 'not saved', and nothing waits for it")
        func yourNameNotSavedAcrossAnAccountChange() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            let hook = ClassroomNames.LookupHook { ClassroomIdentity.currentUserRecordName = "_bea" }
            let (saved, waiting, name) = await ClassroomNames.$zoneLookupHook.withValue(hook) {
                await Support.asDevice(recordName: "_guide") {
                    let saved = await ClassroomYourNameCard.setName("Danny", in: context, save: CoreDataTestHelpers.save)
                    return (saved, ClassroomIdentity.nameWaitingAs, ClassroomIdentity.displayName)
                }
            }
            #expect(saved == .notSaved)
            #expect(waiting == nil, "nothing waits to go in under whoever signs in next")
            #expect(name == nil)
            #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).isEmpty)
            #expect(SettingsCopy.YourName.notSaved.contains("Type your name again"))
        }

        // Bug hunt 2026-10-09, #5: the Assistant forgot a waiting name when
        // another account signed in; the notebook wrote it into that one's row.
        @Test("On the notebook an account change drops a waiting name only once another account is confirmed")
        func accountChangeDropsTheWaitingName() async {
            func change(
                from before: String?, to after: String?, waiting: Bool = true
            ) async -> (String?, CDClassroomMembership.ClassroomRole?) {
                await Support.asDevice(recordName: before, displayName: "Danny") {
                    if waiting { ClassroomNames.markWaiting(as: .leadGuide) }
                    await ClassroomIdentity.accountChanged { ClassroomIdentity.currentUserRecordName = after }
                    return (ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs)
                }
            }
            let another = await change(from: "_guide", to: "_bea")
            #expect(another.0 == nil)
            #expect(another.1 == nil)
            let same = await change(from: "_guide", to: "_guide")
            #expect(same.0 == "Danny")
            #expect(same.1 == .leadGuide)
            // Signed out, offline or not ready: it may be the same account.
            let none = await change(from: "_guide", to: nil)
            #expect(none.0 == "Danny")
            #expect(none.1 == .leadGuide)
            // Typed before any account was known: it's the next account's.
            let unknown = await change(from: nil, to: "_bea")
            #expect(unknown.0 == "Danny")
            #expect(unknown.1 == .leadGuide)
            // Nothing waiting: a notebook in a class as an assistant keeps the
            // name her marks carry.
            let stamped = await change(from: "_guide", to: "_bea", waiting: false)
            #expect(stamped.0 == "Danny")
            #expect(stamped.1 == nil)
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
}
