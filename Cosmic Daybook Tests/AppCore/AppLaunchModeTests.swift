import Testing
@testable import CosmicDaybook

// MARK: - Which launches are MCP-only
//
// The Claude bridge launches the Mac app with `-CosmicDaybookMCPAutolaunch YES`
// when a Claude session starts and the app isn't running; that launch comes up
// with no main window and quits once Claude has gone. Every other launch —
// Finder, the Dock, Xcode (which adds arguments of its own) — must stay a
// normal one, so the parse is strict about what turns the mode on.

@Suite("App launch mode")
struct AppLaunchModeTests {
    private static let executable = "/Applications/Cosmic Daybook.app/Contents/MacOS/Cosmic Daybook"

    @Test("The bridge's launch arguments make an MCP-only launch")
    func bridgeArgumentsAreMCPOnly() {
        let arguments = [
            Self.executable,
            "-CosmicDaybookMCPAutolaunch", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        #expect(AppLaunchMode.resolve(arguments: arguments) == .mcpOnly)
    }

    @Test("Any true spelling turns it on", arguments: ["YES", "yes", "true", "TRUE", "1"])
    func trueSpellings(value: String) {
        #expect(AppLaunchMode.resolve(arguments: [Self.executable, "-CosmicDaybookMCPAutolaunch", value]) == .mcpOnly)
    }

    @Test("A false or missing value is a normal launch", arguments: [["NO"], ["false"], ["0"], ["maybe"], []])
    func falseOrMissingValue(value: [String]) {
        let arguments = [Self.executable, "-CosmicDaybookMCPAutolaunch"] + value
        #expect(AppLaunchMode.resolve(arguments: arguments) == .normal)
    }

    @Test("Finder, Dock and Xcode launches are normal")
    func ordinaryLaunchesAreNormal() {
        #expect(AppLaunchMode.resolve(arguments: [Self.executable]) == .normal)
        #expect(AppLaunchMode.resolve(arguments: []) == .normal)
        // What Xcode passes when it runs the scheme.
        let xcode = [Self.executable, "-NSDocumentRevisionsDebugMode", "YES", "-ApplePersistenceIgnoreState", "YES"]
        #expect(AppLaunchMode.resolve(arguments: xcode) == .normal)
    }

    @Test("Only the exact flag counts")
    func onlyTheExactFlag() {
        #expect(AppLaunchMode.resolve(arguments: [Self.executable, "CosmicDaybookMCPAutolaunch", "YES"]) == .normal)
        #expect(AppLaunchMode.resolve(arguments: [Self.executable, "-CosmicDaybookMCPAutolaunchX", "YES"]) == .normal)
        #expect(AppLaunchMode.resolve(arguments: [Self.executable, "YES", "-CosmicDaybookMCPAutolaunch"]) == .normal)
    }

    @Test("This test process is a normal launch")
    func currentProcessIsNormal() {
        #expect(AppLaunchMode.current == .normal)
    }
}
