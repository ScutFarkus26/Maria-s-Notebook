// WorkCard+GridMenu.swift
// The work card's right-click menu.
//
// Three things this menu got wrong before, all of them silent:
//
//  1. It hung off the metadata line — `Adina T. • Practice • 110d` — so
//     right-clicking the title, the badge, or anywhere else on the card did
//     nothing at all. It is on the whole card now.
//  2. Change Status ▸ Practice / Follow-Up had empty bodies. Two menu items
//     that looked live, clicked fine, and changed nothing.
//  3. It ignored the command-click selection. Right-clicking one of four
//     selected cards acted on one of them, which is the worst possible answer:
//     it looks like it worked.
//
// Every verb here now reads the same targets the labels count, so what the
// menu says is what it does.

import CoreData
import SwiftUI

extension WorkCardGridContent {

    /// The records this menu acts on — this card, or the whole selection when
    /// this card is part of one.
    var menuTargets: [CDWorkModel] {
        config.menuTargets?() ?? [config.work]
    }

    /// Suffixes a verb with the count when it is about to act on several, so a
    /// bulk action can never masquerade as a single one.
    func menuLabel(_ single: String, _ many: (Int) -> String) -> String {
        let count = menuTargets.count
        return count > 1 ? many(count) : single
    }

    @ViewBuilder
    var gridContextMenu: some View {
        let targets = menuTargets
        let isBulk = targets.count > 1

        // Opening is a one-record verb: four detail windows at once is not
        // what anyone means by right-clicking a selection.
        if !isBulk {
            Button {
                config.onOpen(config.work)
            } label: {
                Label("Open", systemImage: "arrow.forward.circle")
            }

            #if os(macOS)
            Button {
                if let id = config.work.id { openWorkInNewWindow(id) }
            } label: {
                Label("Open in New Window", systemImage: "uiwindow.split.2x1")
            }
            #endif
            Divider()
        }

        Button {
            for work in targets { config.onMarkCompleted(work) }
        } label: {
            Label(
                menuLabel("Mark Completed") { "Mark \($0) Completed" },
                systemImage: "checkmark.circle"
            )
        }

        statusMenu(targets)
        scheduleMenu(targets)
        restMenu(targets)

        if !isBulk {
            Divider()
            jumpButtons
            Button {
                copyWorkTitle()
            } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }
        }

        if let onRequestDelete = config.onRequestDelete {
            Divider()
            Button(role: .destructive) {
                onRequestDelete(targets)
            } label: {
                Label(
                    menuLabel("Delete…") { "Delete \($0) Work Items…" },
                    systemImage: "trash"
                )
            }
        }
    }

    // MARK: - Submenus

    /// Practice or Follow-Up. These two used to be empty closures; they write
    /// through `WorkRepository` now, the same path the detail view uses.
    @ViewBuilder
    private func statusMenu(_ targets: [CDWorkModel]) -> some View {
        Menu {
            statusButton("Practice", status: .active, targets: targets)
            statusButton("Follow-Up", status: .review, targets: targets)
        } label: {
            Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    @ViewBuilder
    private func statusButton(
        _ title: String,
        status: WorkStatus,
        targets: [CDWorkModel]
    ) -> some View {
        // A checkmark only when every target already agrees; a mixed selection
        // shows neither rather than claiming one of them.
        let isCurrent = targets.allSatisfy { $0.status == status }
        Button {
            setStatus(status, on: targets)
        } label: {
            Label(title, systemImage: isCurrent ? "checkmark" : "circle")
        }
    }

    /// Today, tomorrow, and — the point of the submenu — any other day.
    ///
    /// This used to be a menu with one item in it, so the only day a card could
    /// name was today; every other day had to be reached by dragging the card
    /// onto the Scheduled strip, which can only offer the days it is showing.
    @ViewBuilder
    private func scheduleMenu(_ targets: [CDWorkModel]) -> some View {
        Menu {
            Button("Today") { schedule(targets, on: AppCalendar.startOfDay(Date())) }
            Button("Tomorrow") {
                schedule(targets, on: AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date())))
            }
            Divider()
            Button("Pick a Day…") { isPickingCheckDay = true }
        } label: {
            Label("Schedule", systemImage: "calendar")
        }
    }

    /// "Not now" without deleting anything.
    ///
    /// `LessonsAndWorkTriage` checks `restingUntil` before every reason to nag,
    /// so this genuinely quiets the card until the date — it moves to the
    /// Scheduled pill rather than sitting in Needs Checking.
    @ViewBuilder
    private func restMenu(_ targets: [CDWorkModel]) -> some View {
        Menu {
            ForEach(WorkRestPreset.allCases) { preset in
                Button(preset.title) { setAside(until: preset.wakeDate(), on: targets) }
            }
            if targets.contains(where: isResting) {
                Divider()
                Button("Bring Back Now") { setAside(until: nil, on: targets) }
            }
        } label: {
            Label("Set Aside Until", systemImage: "moon.zzz")
        }
    }

    @ViewBuilder
    private var jumpButtons: some View {
        if let studentID = UUID(uuidString: config.work.studentID) {
            Button {
                appRouter.requestOpenStudentDetail(studentID)
            } label: {
                Label("Go to \(config.studentDisplay)", systemImage: "person.crop.circle")
            }
        }
        if let lessonID = UUID(uuidString: config.work.lessonID) {
            Button {
                appRouter.navigateToLesson(lessonID)
            } label: {
                Label("Open \(config.lessonTitle)", systemImage: "book")
            }
        }
    }

    // MARK: - Actions

    private func isResting(_ work: CDWorkModel) -> Bool {
        guard let restingUntil = work.restingUntil else { return false }
        return AppCalendar.startOfDay(restingUntil) > AppCalendar.startOfDay(Date())
    }

    /// The one place the card writes a check day, so the menu's fixed days and
    /// the calendar's chosen one land the same way.
    func schedule(_ targets: [CDWorkModel], on day: Date) {
        for work in targets { config.onSchedule(work, day) }
    }

    private func setStatus(_ status: WorkStatus, on targets: [CDWorkModel]) {
        let repository = WorkRepository(context: viewContext)
        for work in targets {
            guard let id = work.id else { continue }
            repository.updateWorkStatus(id: id, status: status)
        }
    }

    private func setAside(until date: Date?, on targets: [CDWorkModel]) {
        for work in targets {
            if let date {
                MeetingReviewService.setWorkResting(work, until: date)
            } else {
                MeetingReviewService.clearWorkResting(work)
            }
        }
        viewContext.safeSave()
    }
}
