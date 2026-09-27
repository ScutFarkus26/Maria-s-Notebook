import Testing
@testable import CosmicDaybook

/// Which open main window the Mac's desktop companion brings forward instead
/// of opening another one.
@Suite("Main window choice")
@MainActor
struct MainWindowCandidateTests {

    private func onScreen(_ lastUsed: Int) -> MainWindowCandidate {
        MainWindowCandidate(isOnScreen: true, isMiniaturized: false, lastUsed: lastUsed)
    }

    private func minimized(_ lastUsed: Int) -> MainWindowCandidate {
        MainWindowCandidate(isOnScreen: false, isMiniaturized: true, lastUsed: lastUsed)
    }

    private func closed(_ lastUsed: Int) -> MainWindowCandidate {
        MainWindowCandidate(isOnScreen: false, isMiniaturized: false, lastUsed: lastUsed)
    }

    @Test("With no main window open, the caller opens one as before")
    func noOpenWindowOpensANewOne() {
        #expect(MainWindowCandidate.indexToBringForward([]) == nil)
        #expect(MainWindowCandidate.indexToBringForward([closed(3)]) == nil)
    }

    @Test("The one open main window comes forward instead of a second one opening")
    func singleOpenWindowIsReused() {
        #expect(MainWindowCandidate.indexToBringForward([onScreen(1)]) == 0)
        #expect(MainWindowCandidate.indexToBringForward([minimized(1)]) == 0)
    }

    @Test("Of several on screen, the most recently used comes forward")
    func mostRecentOnScreenWins() {
        #expect(MainWindowCandidate.indexToBringForward([onScreen(3), onScreen(5), onScreen(4)]) == 1)
    }

    @Test("A window on screen wins over a more recently used one in the Dock")
    func onScreenBeatsMinimized() {
        #expect(MainWindowCandidate.indexToBringForward([minimized(9), onScreen(2)]) == 1)
    }

    @Test("With every main window in the Dock, the most recently used comes out")
    func mostRecentMinimizedComesOut() {
        #expect(MainWindowCandidate.indexToBringForward([minimized(1), minimized(4), closed(7)]) == 1)
    }

    @Test("A closed window is never brought forward")
    func closedWindowIsSkipped() {
        #expect(MainWindowCandidate.indexToBringForward([closed(10), onScreen(1)]) == 1)
    }

    // MARK: - Answering a request every main window hears

    /// The windows that would open a window for one window-opening post.
    private func answering(_ candidates: [MainWindowCandidate]) -> [Int] {
        candidates.indices.filter { MainWindowCandidate.indexToAnswer(candidates) == $0 }
    }

    @Test("Of several main windows hearing one request, only the most recently used on screen answers")
    func oneOfSeveralAnswers() {
        #expect(answering([onScreen(3), onScreen(5), minimized(9), onScreen(4)]) == [1])
        #expect(answering([onScreen(1)]) == [0])
    }

    @Test("With every main window in the Dock, only the most recently used answers")
    func oneMinimizedWindowAnswers() {
        #expect(answering([minimized(2), minimized(6), minimized(4)]) == [1])
    }

    @Test("With none on screen or in the Dock, as while the app is hidden, the most recently used still answers")
    func orderedOutWindowsStillAnswerOnce() {
        #expect(answering([closed(2), closed(7), closed(4)]) == [1])
    }

    @Test("With no main window, nothing answers")
    func noWindowNoAnswer() {
        #expect(MainWindowCandidate.indexToAnswer([]) == nil)
    }
}
