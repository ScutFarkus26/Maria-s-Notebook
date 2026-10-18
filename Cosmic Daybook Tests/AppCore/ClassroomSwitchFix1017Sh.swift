// Bug hunt 2026-10-17 #31: switching classroom rebuilt every window, so a
// sheet or detail window being typed in anywhere lost its text without asking.

import CoreData
import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CosmicDaybook

@Suite("Classroom switch asks first (Fix1017Sh)", .serialized)
@MainActor
struct ClassroomSwitchFix1017ShTests {
    #if os(iOS)
    @Test("The check sees a sheet presented in any window")
    func seesPresentedSheet() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        defer { window.isHidden = true }
        #expect(!OpenEditorsCheck.anySheetPresented(in: [window]))

        root.present(UIViewController(), animated: false)
        try #require(root.presentedViewController != nil)

        #expect(OpenEditorsCheck.anySheetPresented(in: [window]))
        // The app-wide check reads every scene's windows, this one among them.
        #expect(OpenEditorsCheck.anyOpen(detailWindows: OpenDetailWindows()))

        // Leave nothing up for the next test, and see the check let go.
        await withCheckedContinuation { done in
            root.dismiss(animated: false) { done.resume() }
        }
        #expect(!OpenEditorsCheck.anySheetPresented(in: [window]))
    }
    #endif

    @Test("The check sees an open detail window")
    func seesOpenDetailWindow() {
        let windows = OpenDetailWindows()
        let window = UUID()

        windows.opened(window)
        #expect(OpenEditorsCheck.anyOpen(detailWindows: windows))

        // With no sheet up (the test host's own windows aside), a closed
        // window no longer counts.
        windows.closed(window)
        #expect(!OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))
        #expect(OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: true))
    }

    @Test("A switch asks first only while something is open")
    func asksOnlyWhileOpen() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        var isOpen = false
        let store = ClassroomWorkspaceStore(
            primaryStack: stack,
            primaryDependencies: AppDependencies(coreDataStack: stack),
            hasOpenEditors: { isOpen }
        )

        #expect(store.switchRequest(to: .sampleClass) == .switchNow)

        isOpen = true
        #expect(store.switchRequest(to: .sampleClass) == .askFirst)
        // Choosing the classroom already showing rebuilds nothing, so it never asks.
        #expect(store.switchRequest(to: .myClass) == .switchNow)
        // Asking changes nothing by itself.
        #expect(store.selection == .myClass)
    }
}
