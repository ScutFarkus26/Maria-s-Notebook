// TodayViewReadyForNextSection.swift
// Who is waiting on a next lesson, on the day the guide is standing in it.
//
// The queue itself is `ReadyForNextEngine`, already built once per reload by
// TodayViewModel: every child confirmed or mastered on a lesson whose
// successor in the same sub-area is neither on her record nor planned for
// her. This groups it by the lesson being proposed, because forming that
// group is what the guide is about to do — so each row plans it, with the
// ready children already selected.
//
// Almost-ready children are shown dimmed with the reason holding them, never
// preselected: the practice gate is information, not a veto the guide has to
// argue with.

import SwiftUI
import CoreData

extension TodayView {
    var readyForNextListSection: some View {
        ReadyForNextSectionView(items: viewModel.readyForNext)
            // Skip Today's parent passes when the queue is the same value;
            // the catalog and roster reads below still invalidate it.
            .equatable()
    }
}

extension ReadyForNextSectionView: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items
    }
}

struct ReadyForNextSectionView: View {
    let items: [ReadyForNextItem]

    /// How many lesson groups Today shows before it stops listing them.
    private static let groupLimit = 5

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies

    @State private var lessonToPlan: CDLesson?

    var body: some View {
        let groups = buildGroups()
        if !groups.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups.prefix(Self.groupLimit)) { group in
                        groupRow(group)
                    }
                    if groups.count > Self.groupLimit {
                        Text("and \(groups.count - Self.groupLimit) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .sheet(item: $lessonToPlan) { lesson in
                planSheet(for: lesson)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func groupRow(_ group: ReadyGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.lesson.name)
                    .font(.subheadline.weight(.medium))
                if !group.ready.isEmpty {
                    Text(group.ready.map(\.shortName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(group.almost) { entry in
                    Text("\(entry.student.shortName) — \(entry.reason)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Plan") { lessonToPlan = group.lesson }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(group.ready.isEmpty)
        }
    }

    private func planSheet(for lesson: CDLesson) -> some View {
        SchedulePresentationSheet(
            lesson: lesson,
            initialSelection: readyIDs(for: lesson),
            onPlan: { studentIDs, purpose in
                plan(lesson: lesson, studentIDs: studentIDs, purpose: purpose)
                lessonToPlan = nil
            },
            onCancel: { lessonToPlan = nil }
        )
    }

    private func plan(lesson: CDLesson, studentIDs: Set<UUID>, purpose: RepeatPurpose?) {
        guard PresentationPlanner.planDraft(
            lesson: lesson, studentIDs: studentIDs, purpose: purpose, in: viewContext
        ) != nil else { return }
        saveCoordinator.save(viewContext, reason: "Plan presentation")
    }

    // MARK: - Grouping

    /// One lesson the queue proposes, with the children waiting on it.
    private struct ReadyGroup: Identifiable {
        let lesson: CDLesson
        let ready: [CDStudent]
        let almost: [AlmostReady]
        var id: String { lesson.id?.uuidString ?? lesson.name }
    }

    /// A child a gate still holds, and the sentence saying so.
    private struct AlmostReady: Identifiable {
        let student: CDStudent
        let reason: String
        var id: String { (student.id?.uuidString ?? student.fullName) + reason }
    }

    /// The queue folded onto the lessons it proposes, busiest group first so
    /// the cap keeps the groups worth forming.
    private func buildGroups() -> [ReadyGroup] {
        guard !items.isEmpty else { return [] }
        // The live catalog's and roster's `byID` keep the first row per ID,
        // as the String-keyed dictionaries built here per render used to.
        let lessonsByID = dependencies.lessonCatalog.byID
        let studentsByID = dependencies.roster.byID

        let grouped: [String: [ReadyForNextItem]] = Dictionary(grouping: items, by: \.nextLessonID)
        let groups: [ReadyGroup] = grouped.compactMap { lessonID, entries in
            guard let lesson = UUID(uuidString: lessonID).flatMap({ lessonsByID[$0] }) else { return nil }
            return makeGroup(lesson: lesson, entries: entries, studentsByID: studentsByID)
        }
        return groups.sorted { lhs, rhs in
            if lhs.ready.count != rhs.ready.count { return lhs.ready.count > rhs.ready.count }
            return lhs.lesson.name.localizedCaseInsensitiveCompare(rhs.lesson.name) == .orderedAscending
        }
    }

    private func makeGroup(
        lesson: CDLesson, entries: [ReadyForNextItem], studentsByID: [UUID: CDStudent]
    ) -> ReadyGroup? {
        var ready: [CDStudent] = []
        var almost: [AlmostReady] = []
        for entry in entries {
            guard let student = UUID(uuidString: entry.studentID).flatMap({ studentsByID[$0] }) else { continue }
            if entry.tier == .ready {
                ready.append(student)
            } else {
                almost.append(AlmostReady(student: student, reason: entry.reasons.joined(separator: "; ")))
            }
        }
        guard !ready.isEmpty || !almost.isEmpty else { return nil }
        ready.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        almost.sort {
            $0.student.fullName.localizedCaseInsensitiveCompare($1.student.fullName) == .orderedAscending
        }
        return ReadyGroup(lesson: lesson, ready: ready, almost: almost)
    }

    /// The ids the Plan sheet starts with: the ready children only.
    private func readyIDs(for lesson: CDLesson) -> Set<UUID> {
        guard let lessonID = lesson.id?.uuidString else { return [] }
        let ready = items.filter { $0.nextLessonID == lessonID && $0.tier == .ready }
        return Set(ready.compactMap { UUID(uuidString: $0.studentID) })
    }
}
