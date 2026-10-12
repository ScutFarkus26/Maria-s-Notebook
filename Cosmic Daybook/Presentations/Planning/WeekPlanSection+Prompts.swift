// WeekPlanSection+Prompts.swift
// The strip's questions and the refreshes that go with them: a later pill's
// "Open whose work?", Move All Forward's "Move N … forward?" with its Undo,
// and the card data's reload when a child or lesson changes.
//
// Split from WeekPlanSection+Data.swift for SwiftLint's file-length limit; the
// state these read is declared in WeekPlanSection.swift.

import Combine
import SwiftUI
import CoreData

extension WeekPlanSection {
    /// What a later pill's "Open whose work?" question says: "This check is
    /// for Thursday. …"
    static func laterPillMessage(for day: Date, today: Date = Date()) -> String {
        let name = TodayBumpDay.name(for: day, today: today, calendar: AppCalendar.shared)
        return "This check is for \(name), so it's logged then. To log it now, move it to today from its menu."
    }

    /// Move All Forward asks first, naming what it would move: what the Show
    /// filter shows, from today on (bug hunt 2026-10-12, #49).
    func askToMoveAllForward() {
        let pending = CalendarForwardShiftService.pending(
            in: viewContext, calendar: calendar, kinds: visibleKinds, from: Date()
        )
        guard !pending.isEmpty else {
            dependencies.toastService.show(
                "Nothing is scheduled from today on to move.", type: .info, duration: 3
            )
            return
        }
        pendingShift = pending
    }

    /// "Move 3 presentations and 5 work checks forward?"
    static func moveForwardTitle(for pending: CalendarForwardShiftService.Result) -> String {
        var parts: [String] = []
        if pending.presentations > 0 {
            parts.append(pending.presentations == 1 ? "1 presentation" : "\(pending.presentations) presentations")
        }
        if pending.checkIns > 0 {
            parts.append(pending.checkIns == 1 ? "1 work check" : "\(pending.checkIns) work checks")
        }
        return "Move \(parts.joined(separator: " and ")) forward?"
    }

    static let moveForwardMessage = "Each moves to the next school day. Earlier days, finished work "
        + "and anything the Show filter hides stay where they are."

    /// Slides what the strip shows, from today on, one school day later —
    /// presentations and the work checks alongside them — and offers Undo.
    /// See `CalendarForwardShiftService` for the rule.
    func moveAllScheduledForward() async {
        let result = CalendarForwardShiftService.moveForwardOneDayAndSave(
            in: viewContext,
            calendar: calendar,
            kinds: visibleKinds,
            from: Date(),
            nextSchoolDay: { day in
                SchoolCalendarService.shared.nextSchoolDaySync(after: day, using: viewContext)
            },
            persist: {
                saveCoordinator.save(
                    viewContext,
                    reason: "Move all scheduled presentations and work forward one day"
                )
            }
        )
        guard let moved = result else {
            // The save failure alert has said so, and the move was taken back
            // rather than leave the strip showing a move that wasn't saved.
            await refreshCheckIns()
            return
        }
        guard !moved.isEmpty else { return }
        await refreshCheckIns()
        let receipt = moved.receipt
        dependencies.toastService.show("Moved forward one school day", type: .success, duration: 5) {
            CalendarForwardShiftService.undo(receipt, in: viewContext, calendar: calendar)
            saveCoordinator.save(viewContext, reason: "Undo moving the plan forward one day")
            Task { await refreshCheckIns() }
        }
    }
}

extension View {
    /// The strip's card-data refresh, a later pill's "Open whose work?" and
    /// Move All Forward's question, attached in `WeekPlanSection.body`.
    func weekPlanPrompts(_ section: WeekPlanSection) -> some View {
        section.attachMoveForwardDialog(to: section.attachLaterPillDialog(to: section.attachCardRefresh(to: self)))
    }
}

extension WeekPlanSection {
    /// The roster and curriculum the cards name, for `refreshCardData`.
    nonisolated static let cardEntityNames: Set<String> = ["Lesson", "Student"]

    /// Saves touching a child or a lesson, coalesced.
    private var cardDataSaves: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            // @Sendable: runs on the saving context's queue.
            .filter { @Sendable (note: Notification) -> Bool in
                ManagedObjectChangeScope.saveTouches(Self.cardEntityNames, in: note.userInfo)
            }
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }

    /// A child added or renamed, or a lesson edited, after the strip opened:
    /// the cards read the cached roster and curriculum, so they reload with it
    /// rather than dropping her chip (bug hunt 2026-10-12, #50). And when the
    /// test-students setting changes.
    func attachCardRefresh<Content: View>(to content: Content) -> some View {
        content
            .onReceiveWhenVisible(cardDataSaves) { refreshCardData() }
            .onChange(of: testStudents.show) { _, _ in refreshCardData() }
            .onChange(of: testStudents.namesRaw) { _, _ in refreshCardData() }
    }

    private var laterPillShown: Binding<Bool> {
        Binding(get: { laterPill != nil }, set: { if !$0 { laterPill = nil } })
    }

    func attachLaterPillDialog<Content: View>(to content: Content) -> some View {
        content.confirmationDialog(
            "Open whose work?", isPresented: laterPillShown, titleVisibility: .visible, presenting: laterPill
        ) { (group: CalendarCheckInGroup) in
            ForEach(children(of: rows(of: group))) { (child: WorkLogStatusMenu.Child) in
                Button(child.name) {
                    laterPill = nil
                    onOpenWork(child.id)
                }
            }
            Button("Cancel", role: .cancel) { laterPill = nil }
        } message: { (group: CalendarCheckInGroup) in
            Text(Self.laterPillMessage(for: group.sortDate))
        }
    }

    private var pendingShiftShown: Binding<Bool> {
        Binding(get: { pendingShift != nil }, set: { if !$0 { pendingShift = nil } })
    }

    private var pendingShiftTitle: String {
        pendingShift.map(Self.moveForwardTitle(for:)) ?? ""
    }

    func attachMoveForwardDialog<Content: View>(to content: Content) -> some View {
        content.confirmationDialog(
            pendingShiftTitle, isPresented: pendingShiftShown, titleVisibility: .visible, presenting: pendingShift
        ) { (_: CalendarForwardShiftService.Result) in
            Button("Move Forward") {
                pendingShift = nil
                Task { await moveAllScheduledForward() }
            }
            Button("Cancel", role: .cancel) { pendingShift = nil }
        } message: { (_: CalendarForwardShiftService.Result) in
            Text(Self.moveForwardMessage)
        }
    }
}
