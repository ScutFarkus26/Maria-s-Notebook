// TodayView+AbsentMove.swift
// The Lessons header, and moving absent children to the next school day.
//
// The header reads "Lessons · 0 of 4 given". When attendance marks children
// on the day's lessons absent it adds a line — "3 children on today's lessons
// are absent · Move them to tomorrow" (or "to Monday": the next school day,
// `TodayBumpDay`) — and each such lesson offers the same move for itself (an
// inline link and its context menu). The move is `TodayAbsentMover`'s, in one
// save, with Undo on the toast. Never automatic.

import SwiftUI

extension TodayView {

    // MARK: - Header

    /// The day's lessons not yet given — the ones absent children can move off.
    private var lessonsAwaitingPresentation: [CDLessonAssignment] {
        viewModel.todaysLessons.filter { !$0.isPresented }
    }

    @ViewBuilder
    var lessonsSectionHeader: some View {
        let lessons = viewModel.todaysLessons
        let given = lessons.count(where: \.isPresented)
        let absentCount = TodayLessonAttendance.absentChildren(
            onLessons: lessonsAwaitingPresentation.map(\.resolvedStudentIDs),
            absent: viewModel.absentStudentIDs
        ).count
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(
                lessons.isEmpty
                    ? "Lessons"
                    : "Lessons · \(TodayLessonAttendance.givenText(given: given, total: lessons.count))"
            )
            if absentCount > 0 {
                HStack(spacing: 4) {
                    Text(TodayLessonAttendance.absentSummary(count: absentCount))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Button("Move them to \(bumpTargetName)") {
                        moveAbsentToTomorrow(from: lessonsAwaitingPresentation)
                    }
                    .buttonStyle(.borderless)
                    .help("Moves every absent child onto their lesson on the next school day; the others stay")
                }
                .font(AppTheme.ScaledFont.caption)
                .textCase(nil)
            }
        }
    }

    // MARK: - Chips

    /// A lesson's children as chips, the absent ones marked.
    func lessonChips(for sl: CDLessonAssignment, absent: Set<UUID>) -> [TodayStudentChips.Chip] {
        TodayLessonAttendance(studentIDs: sl.resolvedStudentIDs, absent: absent).children.map {
            TodayStudentChips.Chip(id: $0.id, name: displayNameForID($0.id), isAbsent: $0.isAbsent)
        }
    }

    // MARK: - Moving

    /// The day a bump or move lands on: the next school day after the day
    /// shown (`TodayBumpDay.base`), not after the item's own date (see
    /// `bumpLessonToTomorrow`).
    func bumpTargetDay() -> Date? {
        nextSchoolDaySync(after: TodayBumpDay.base(showing: viewModel.date, now: Date(), calendar: calendar))
    }

    /// That day's name for running text: "tomorrow", "Monday".
    var bumpTargetName: String {
        guard let day = bumpTargetDay() else { return "tomorrow" }
        return TodayBumpDay.name(for: day, today: Date(), calendar: calendar)
    }

    /// That day's name for a menu title: "Tomorrow", "Monday".
    var bumpTargetTitle: String {
        guard let day = bumpTargetDay() else { return "Tomorrow" }
        return TodayBumpDay.title(for: day, today: Date(), calendar: calendar)
    }

    func moveAbsentToTomorrow(from lessons: [CDLessonAssignment]) {
        guard let tomorrow = bumpTargetDay() else { return }
        do {
            guard let receipt = try TodayAbsentMover.moveAbsent(
                from: lessons,
                absent: viewModel.absentStudentIDs,
                to: tomorrow,
                context: viewContext,
                saveCoordinator: saveCoordinator
            ) else { return }
            viewModel.reload()
            let names = receipt.movedStudentIDs.map { displayNameForID($0) }.sorted()
            dependencies.toastService.show(
                "Moved \(PresentationSessionSummary.list(names)) to \(bumpTargetName)",
                type: .success,
                duration: 6,
                undoAction: { undoAbsentMove(receipt) }
            )
        } catch {
            dependencies.toastService.showError(error.localizedDescription)
        }
    }

    private func undoAbsentMove(_ receipt: TodayAbsentMover.Receipt) {
        do {
            try TodayAbsentMover.undo(receipt, context: viewContext, saveCoordinator: saveCoordinator)
            viewModel.reload()
        } catch {
            dependencies.toastService.showError(error.localizedDescription)
        }
    }
}
