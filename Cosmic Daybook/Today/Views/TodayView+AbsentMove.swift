// TodayView+AbsentMove.swift
// The Lessons header, and moving absent children to tomorrow.
//
// The header reads "Lessons · 0 of 4 given". When attendance marks children
// on the day's lessons absent it adds a line — "3 children on today's lessons
// are absent · Move them to tomorrow" — and each such lesson offers the same
// move for itself (an inline link and its context menu). The move is
// `TodayAbsentMover`'s, in one save, with Undo on the toast. Never automatic.

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
                    Button("Move them to tomorrow") {
                        moveAbsentToTomorrow(from: lessonsAwaitingPresentation)
                    }
                    .buttonStyle(.borderless)
                    .help("Moves every absent child onto their lesson tomorrow; the others stay")
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

    /// The day a bump lands on: tomorrow relative to today, not to the item's
    /// own date (see `bumpLessonToTomorrow`).
    func bumpTargetDay() -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
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
                "Moved \(PresentationSessionSummary.list(names)) to tomorrow",
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
