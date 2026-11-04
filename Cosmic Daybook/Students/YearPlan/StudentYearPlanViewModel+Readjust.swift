import Foundation
import CoreData

/// What Readjust would do, worked out before anything is written: every
/// target it would move, and the day each would go to. The year plan asks
/// with its counts first ("Move 14 lessons in 3 sequences?"), since Readjust
/// rewrites dates across every sequence at once and has no Undo (bug hunt
/// 2026-11-03 #31, D1).
struct YearPlanReadjustPlan {
    let moves: [YearPlanPacing.Move]

    var isEmpty: Bool { moves.isEmpty }

    var lessonCount: Int { moves.count }

    var sequenceCount: Int { Set(moves.map(\.entry.sequenceGroupKey)).count }

    /// The confirmation's title.
    var question: String {
        let lessons = lessonCount == 1 ? "1 lesson" : "\(lessonCount) lessons"
        let sequences = sequenceCount == 1 ? "1 sequence" : "\(sequenceCount) sequences"
        return "Move \(lessons) in \(sequences)?"
    }

    /// The confirmation's button.
    var actionTitle: String { lessonCount == 1 ? "Move Lesson" : "Move Lessons" }
}

extension StudentYearPlanViewModel {

    /// Readjust's moves for the entries still ahead of this child, sequence by
    /// sequence. Writes nothing; `readjust(_:studentID:context:)` does.
    ///
    /// Two things send a sequence back to the drawing board, and they are
    /// handled differently. A sequence whose first entry has fallen behind pace
    /// is re-laid from the next school day — it has slipped as a whole. A
    /// sequence that is on time but has targets sitting on days the school is
    /// closed is only nudged: those entries move to the open days around them
    /// (`YearPlanPacing.resettle`) and the ones already on good days keep the
    /// dates the guide chose. An entry already on the day it would get is not
    /// a move, so the count is only what changes.
    func readjustPlan(context: NSManagedObjectContext) -> YearPlanReadjustPlan {
        let today = AppCalendar.startOfDay(Date())
        let stillAhead = entries.filter { $0.isPlanned && !$0.isSatisfied(by: satisfaction) }
        let grouped = Dictionary(grouping: stillAhead) { $0.sequenceGroupKey }
        var moves: [YearPlanPacing.Move] = []

        for key in grouped.keys.sorted() {
            let sorted = YearPlanPacing.inSequenceOrder(grouped[key] ?? [])
            guard let first = sorted.first, let firstDate = first.plannedDate else { continue }

            if firstDate < today {
                var currentDate = YearPlanPacing.schoolDay(
                    onOrAfter: AppCalendar.addingDays(1, to: today), in: context
                )
                for (index, entry) in sorted.enumerated() {
                    if index > 0 {
                        currentDate = YearPlanPacing.advance(
                            from: currentDate, bySchoolDays: entry.spacingSchoolDays, in: context
                        )
                    }
                    if entry.plannedDate.map({ AppCalendar.startOfDay($0) }) != currentDate {
                        moves.append(YearPlanPacing.Move(entry: entry, date: currentDate))
                    }
                }
            } else {
                moves += YearPlanPacing.resettleMoves(sorted, in: context)
            }
        }
        return YearPlanReadjustPlan(moves: moves)
    }

    /// Makes the moves the guide agreed to, saves, and reloads. An entry
    /// deleted since the question was asked is left out.
    func readjust(_ plan: YearPlanReadjustPlan, studentID: UUID, context: NSManagedObjectContext) async {
        YearPlanPacing.apply(plan.moves)
        context.safeSave()
        load(studentID: studentID, context: context)
    }
}
