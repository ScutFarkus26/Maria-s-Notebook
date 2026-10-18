// RootView+WindowActions.swift
// This window's own actions for the menu bar and the screens inside it:
// File > New's quick-capture set, New Lesson / New Student, and the Go menu.
// Each acts in this window only (see AppCommands.swift).

import OSLog
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
            openLessonsAndWork: { openLessonsAndWorkInThisWindow($0) },
            switchClassroom: { requestClassroomSwitch(to: $0) },
            continueHandoff: { continueHandoffInThisWindow($0) }
        ))
    }

    /// The Classroom menu's and this window's classroom controls' switch: at
    /// once when nothing is open that it would lose, else after asking over
    /// whatever is in front in this window, a sheet included (bug hunt
    /// 2026-10-17 #31, review c #1).
    func requestClassroomSwitch(to workspace: ClassroomWorkspace) {
        let store = classroomWorkspace
        Task {
            await store.requestSwitch(to: workspace) { proceed in
                if !ClassroomSwitchQuestion.ask(onSwitch: { Task { await proceed() } }) {
                    Self.logger.warning("No window to ask about a classroom switch in; nothing switched")
                }
            }
        }
    }

    /// A Handoff this window took (`WindowHandoff`): its section opens here,
    /// not in whichever main window sees the router first (review c #3).
    private func continueHandoffInThisWindow(_ destination: Handoff.Destination) {
        appRouter.continueHandoff(to: destination) { selectInThisWindow($0) }
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
