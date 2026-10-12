//
//  ReadyLessonPlanSheet.swift
//  Cosmic Daybook
//
//  Planning a lesson the ready queue proposes, from Today's row or a Groups
//  card: the schedule sheet with the ready children already selected, and a
//  draft through `PresentationPlanner` when the guide plans it (undated, as
//  every draft the sheet makes). No alert, and nothing is written on Cancel.
//  A planned child leaves the queue once it rebuilds, so a card offers her once.
//

import CoreData
import SwiftUI

/// A lesson to plan and the children to start with selected.
struct ReadyLessonPlan: Identifiable {
    let lesson: CDLesson
    /// The ready children only; almost-ready ones are never preselected.
    let readyStudentIDs: Set<UUID>

    var id: NSManagedObjectID { lesson.objectID }
}

struct ReadyLessonPlanSheet: View {
    let plan: ReadyLessonPlan
    let onDone: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    var body: some View {
        SchedulePresentationSheet(
            lesson: plan.lesson,
            initialSelection: plan.readyStudentIDs,
            onPlan: { studentIDs, purpose in
                save(studentIDs: studentIDs, purpose: purpose)
                onDone()
            },
            onCancel: onDone
        )
    }

    /// A child already waiting for the lesson isn't planned for it twice
    /// (bug hunt 2026-10-12, #32). When every child already is, the guide is
    /// told so, and told when a chosen reason wasn't added, rather than the
    /// sheet closing without a word.
    private func save(studentIDs: Set<UUID>, purpose: RepeatPurpose?) {
        guard let result = PresentationPlanner.planOrReuse(
            lesson: plan.lesson, studentIDs: studentIDs, purpose: purpose, in: viewContext
        ) else { return }
        guard result.isNew else {
            ToastService.shared.show(
                PresentationPlanner.alreadyPlannedMessage(purpose: purpose), type: .info, duration: 4
            )
            return
        }
        saveCoordinator.save(viewContext, reason: "Plan presentation")
    }
}
