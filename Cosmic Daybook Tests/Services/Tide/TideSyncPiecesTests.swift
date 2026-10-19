import Foundation
import Testing
@testable import CosmicDaybook

/// The Tide sharing's small parts: the address, Tide's links, the name and
/// word matching, where it may run, and reading a reply off the wire.
@Suite("Tide sync pieces")
@MainActor
struct TideSyncPiecesTests {

    // MARK: - Names

    private static let ettyKlein = TideNameMatcher.Child(id: UUID(), firstName: "Etty", lastName: "Klein")
    private static let ettyRosen = TideNameMatcher.Child(id: UUID(), firstName: "Etty", lastName: "Rosen")
    private static let maya = TideNameMatcher.Child(id: UUID(), firstName: "Maya", lastName: "Smith")
    private static let matcher = TideNameMatcher(children: [ettyKlein, ettyRosen, maya])

    @Test("With two Ettys, a bare \"Etty\" names nobody; the short form or full name names one")
    func twoEttys() {
        #expect(Self.matcher.children(namedIn: "Check in with Etty about spelling").isEmpty)
        #expect(Self.matcher.children(namedIn: "Etty K. needs the bead frame") == [Self.ettyKlein.id])
        #expect(Self.matcher.children(namedIn: "Reading with Etty Rosen") == [Self.ettyRosen.id])
        #expect(Self.matcher.children(namedIn: "Etty Klein and Etty R") == [Self.ettyKlein.id, Self.ettyRosen.id])
    }

    @Test("A unique first name names its child, as a whole word only")
    func uniqueFirstName() {
        #expect(Self.matcher.children(namedIn: "Maya's map test") == [Self.maya.id])
        #expect(Self.matcher.children(namedIn: "MAYA S to present") == [Self.maya.id])
        #expect(Self.matcher.children(namedIn: "Mayan calendar lesson").isEmpty)
        #expect(Self.matcher.children(namedIn: "Etty Kleinman's folder").isEmpty, "Etty K isn't Etty Kleinman")
    }

    @Test("Two children sharing a short form leave it to their full names")
    func sharedShortForm() {
        let one = TideNameMatcher.Child(id: UUID(), firstName: "Sarah", lastName: "Cohen")
        let two = TideNameMatcher.Child(id: UUID(), firstName: "Sarah", lastName: "Cooper")
        let matcher = TideNameMatcher(children: [one, two])
        #expect(matcher.children(namedIn: "Sarah C's book").isEmpty)
        #expect(matcher.children(namedIn: "Sarah Cooper's book") == [two.id])
    }

    // MARK: - Words

    @Test("The first run matches titles by their words, one to one")
    func wordMatching() {
        #expect(TideWordMatch.score("Order more pin maps", "Order pin maps") >= TideWordMatch.threshold)
        #expect(TideWordMatch.score("MAP testing", "Set up MAP testing for the fall") >= TideWordMatch.threshold)
        #expect(TideWordMatch.score("Order pin maps", "Label the shelves") < TideWordMatch.threshold)

        let pins = Self.notebook("Order more pin maps")
        let shelves = Self.notebook("Label shelves")
        let pairs = TideWordMatch.pairs(
            notebook: [pins, shelves],
            tide: [Self.tide("Order pin maps"), Self.tide("Order pin maps and tape"), Self.tide("Label the shelves")]
        )
        #expect(pairs.count == 2)
        #expect(Set(pairs.map(\.notebookID)) == [pins.id, shelves.id])
        #expect(Set(pairs.map(\.tideLink)).count == 2, "one action per to-do")
    }

    @Test("An action carrying a to-do's notebook line is that to-do's match, whatever the words")
    func markerBeatsWords() throws {
        let todo = Self.notebook("Plan the field trip")
        let action = Self.tide("Book the bus", note: TideNotebookMarker.line(for: todo.id))
        let pairs = TideWordMatch.pairs(notebook: [todo], tide: [action])
        #expect(pairs.first?.score == 1)
        #expect(TideNotebookMarker.todoID(in: "For Maya.\n\nnotebook:\(todo.id.uuidString)") == todo.id)
        #expect(TideNotebookMarker.removing(from: "Use tape.\n\nnotebook:\(todo.id.uuidString)") == "Use tape.")
    }

    // MARK: - Links

    @Test("A link is spelled exactly as Tide spells it, and reads back")
    func linkSpelling() throws {
        let link = TideActionLink(file: "Areas/My Classrooms/Upper Elementary/To do.md", text: "Pins — 2 sets & tape")
        #expect(link.string == "tide://box/Areas/My%20Classrooms/Upper%20Elementary/To%20do.md"
            + "?text=Pins%20%E2%80%94%202%20sets%20%26%20tape")
        let read = try #require(TideActionLink(link.string))
        #expect(read == link)
        #expect(read.listName == "Upper Elementary")
        #expect(TideActionLink.listName(ofFile: "Areas/My Classrooms/To do.md") == "My Classrooms")
        #expect(TideActionLink("tide://area/Home") == nil)
    }

    // MARK: - Address

    @Test("A pasted address is kept as localhost with its token; anything else is explained")
    func addressParsing() throws {
        let token = String(repeating: "a1", count: 20)
        let good = try TideAddress.parse("  http://localhost:4877/\(token)/mcp\n").get()
        #expect(good.url.absoluteString == "http://localhost:4877/\(token)/mcp")
        let numeric = try TideAddress.parse("http://127.0.0.1:4877/\(token)/mcp").get()
        #expect(numeric.url.host() == "localhost", "App Transport Security allows a host name, not an IP address")
        #expect(TideAddress.parse("") == .failure(.empty))
        #expect(TideAddress.parse("http://localhost:4877/mcp") == .failure(.missingToken))
        #expect(TideAddress.parse("http://example.com:4877/\(token)/mcp") == .failure(.notOnThisMac))
        #expect(TideAddress.parse("https://localhost:4877/\(token)/mcp") == .failure(.notTideAddress))
        for problem in [TideAddress.Problem.empty, .notTideAddress, .notOnThisMac, .missingToken] {
            #expect(problem.errorDescription?.contains("Settings › Claude") == true)
        }
    }

    // MARK: - Where it runs

    @Test("Only a Release build of the Mac app outside a test run talks to Tide")
    func policy() {
        #expect(TideSyncPolicy.resolve(isMac: false, isDebugBuild: false, environment: [:]) == .notOnThisDevice)
        #expect(TideSyncPolicy.resolve(isMac: true, isDebugBuild: true, environment: [:]) == .testCopy)
        #expect(TideSyncPolicy.resolve(
            isMac: true, isDebugBuild: false, environment: ["XCTestConfigurationFilePath": "x"]
        ) == .testCopy)
        #expect(TideSyncPolicy.resolve(isMac: true, isDebugBuild: false, environment: [:]) == .live)
        #expect(TideSyncPolicy.current != .live, "this test run never reaches Tide")
    }

    // MARK: - Wire

    @Test("A tool reply is read off a JSON-RPC response; a refusal keeps its rule for Details")
    func readsReplies() throws {
        let body = #"{"jsonrpc":"2.0","id":"daybook-1","result":"#
            + #"{"content":[{"type":"text","text":"{\"ok\":true}"}],"isError":false}}"#
        let reply = try TideHTTPTransport.toolReply(from: Data(body.utf8))
        #expect(reply == TideToolReply(text: #"{"ok":true}"#, isError: false))

        let error = #"{"jsonrpc":"2.0","id":"daybook-2","error":{"code":-32601,"message":"Method not found"}}"#
        #expect(throws: TideTransportError.self) { try TideHTTPTransport.toolReply(from: Data(error.utf8)) }

        let call = TideRPCCall(id: .string("daybook-3"), method: "tools/call", params: .object(["name": "get_area"]))
        let sent = try #require(String(bytes: try JSONEncoder().encode(call), encoding: .utf8))
        #expect(sent.contains(#""jsonrpc":"2.0""#))
        #expect(sent.contains(#""method":"tools\/call""#))
    }

    // MARK: - Helpers

    private static func notebook(_ title: String) -> TideNotebookTodo {
        TideNotebookTodo(id: UUID(), title: title, notes: "", isCompleted: false, hasLinkedWork: false,
                         isSomeday: false, tideLink: nil, studentIDs: [], dueDate: nil, scheduledDate: nil,
                         createdAt: nil)
    }

    private static func tide(_ text: String, note: String? = nil) -> TideAction {
        TideAction(action: text, note: note, file: FakeTide.roomSetup, position: 1, of: 1, revision: "r")
    }
}
