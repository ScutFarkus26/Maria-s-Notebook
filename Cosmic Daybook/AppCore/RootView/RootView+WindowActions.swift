// RootView+WindowActions.swift
// This window's own actions for the menu bar and the screens inside it:
// File > New's quick-capture set, New Lesson / New Student, and the Go menu.
// Each acts in this window only (see AppCommands.swift).

import SwiftUI

extension RootView {
    /// File > New's quick-capture actions — the radial menu's set — and the
    /// Go menu's section switches.
    func installQuickCaptureHandlers() {
        quickCaptureActions.setHandlers(QuickCaptureActions.Handlers(
            newPresentation: { createPresentationDraft() },
            newWork: { activeSheet = .newWorkItem(lessonID: nil, studentIDs: []) },
            recordPractice: { activeSheet = .recordPractice },
            newTodo: { activeSheet = .newTodo(initialTitle: "") },
            newNote: { activeSheet = .quickNote(QuickNoteParams()) },
            openCommandBar: { activeSheet = .commandBar },
            newLesson: { askInThisWindow(.newLesson(defaultArea: nil, defaultSequence: nil)) },
            newStudent: { askInThisWindow(.newStudent) },
            importStudents: { askInThisWindow(.importStudents) },
            goTo: { goInThisWindow($0) },
            openLessonsAndWork: { openLessonsAndWorkInThisWindow($0) }
        ))
    }

    /// Goes to the section that answers `request` in this window and leaves
    /// the request for that section's screen, which opens its sheet on appear
    /// or, already on screen, at once.
    private func askInThisWindow(_ request: WindowCreateRequests.Request) {
        createRequests.ask(request)
        selectInThisWindow(request.answeringSection)
    }

    /// The Go menu's switch, as `AppRouter.navigateTo` makes it but for this
    /// window only.
    private func goInThisWindow(_ item: NavigationItem) {
        let route = WindowSectionRequests.route(to: item)
        if let lens = route.lessonsAndWork {
            openLessonsAndWorkInThisWindow(lens)
        } else {
            selectInThisWindow(route.section)
        }
    }

    /// Opens this window's Lessons & Work on `request`'s lens. The workspace
    /// takes the lens on appear or, already on screen, at once.
    private func openLessonsAndWorkInThisWindow(_ request: AppRouter.LessonsAndWorkRequest) {
        sectionRequests.ask(request)
        selectInThisWindow(.planningAgenda)
    }

    private func selectInThisWindow(_ item: NavigationItem) {
        if selectedNavItem != item {
            selectedNavItem = item
        }
    }
}
