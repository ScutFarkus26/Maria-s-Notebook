// TodayViewReadyForNextSection.swift
// Who is waiting on a next lesson, on the day the guide is standing in it.
//
// The queue itself is `ReadyForNextEngine`, built by Today's
// `ReadyQueueLoader`: every child confirmed or mastered on a lesson whose
// successor in the same sub-area is neither on her record nor planned for
// her. `ReadyGroups` folds it onto the lessons it proposes, in the Groups
// page's order (ready count, longest wait, name), because forming that group
// is what the guide is about to do — so each row plans it, with the ready
// children already selected. The top five show here; "See all in Groups"
// opens the rest, with no number that could disagree with the page.
//
// Almost-ready children are shown dimmed with the reason holding them, never
// preselected: the practice gate is information, not a veto the guide has to
// argue with. A lesson only held children wait on is listed with Plan off.

import SwiftUI
import CoreData

extension TodayView {
    var readyForNextListSection: some View {
        // Today's parent passes are skipped when the queue is the same value:
        // SwiftUI compares a view that holds non-trivial state with its own
        // `Equatable` conformance (below). Not `.equatable()` — inside a List
        // the `EquatableView` wrapper is a row of its own, so an empty queue
        // left a blank card on Today.
        ReadyForNextSectionView(
            snapshot: viewModel.readyQueue.snapshot,
            version: viewModel.readyQueue.publishCount
        )
    }
}

extension ReadyForNextSectionView: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version
    }
}

struct ReadyForNextSectionView: View {
    let snapshot: ReadyQueueSnapshot?
    /// Moves exactly when `snapshot` is replaced (`ReadyQueueLoader.publishCount`).
    let version: Int

    /// How many lesson groups Today shows before it points at the Groups page.
    private static let groupLimit = 5

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appRouter) private var appRouter

    @State private var lessonToPlan: ReadyLessonPlan?

    var body: some View {
        let lessons = buildLessons()
        if !lessons.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lessons.prefix(Self.groupLimit)) { group in
                        groupRow(group)
                    }
                    seeAllLink
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            } header: {
                Text("Ready for a next lesson")
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .sheet(item: $lessonToPlan) { plan in
                ReadyLessonPlanSheet(plan: plan) { lessonToPlan = nil }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func groupRow(_ group: LessonGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.lessonName)
                    .font(.subheadline.weight(.medium))
                if !group.ready.isEmpty {
                    Text(group.ready.map(\.child.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(group.almost) { member in
                    Text("\(member.child.name) — \(member.reason ?? "")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Plan") { plan(group) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(group.ready.isEmpty)
        }
    }

    private var seeAllLink: some View {
        Button {
            appRouter.navigateTo(.smallSequencePlanner)
        } label: {
            HStack(spacing: 4) {
                Text("See all in Groups")
                Image(systemName: "chevron.right")
                    .imageScale(.small)
            }
            .font(.subheadline)
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func plan(_ group: LessonGroup) {
        guard let lesson = dependencies.lessonCatalog.byID[group.lessonUUID] else { return }
        lessonToPlan = ReadyLessonPlan(lesson: lesson, readyStudentIDs: group.readyStudentUUIDs)
    }

    // MARK: - Grouping

    /// Every lesson the queue proposes, busiest group first so the cap keeps
    /// the groups worth forming. Lessons only held children wait on stay in.
    private func buildLessons() -> [LessonGroup] {
        guard let snapshot, !snapshot.items.isEmpty else { return [] }
        let context = viewContext
        return ReadyGroups.build(from: snapshot) {
            LessonAgeHelper.schoolDaysSinceCreation(createdAt: $0, using: context)
        }.lessons
    }
}
