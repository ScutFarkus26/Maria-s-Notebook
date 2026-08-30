// LessonsAndWorkToScheduleView.swift
// The "what still has to be planned" list.
//
// Everything here has no day on it: presentations that are ready but
// unscheduled, and open work with neither a due date nor a check-in. Both are
// drag sources for the Scheduled calendar, which is how something leaves this
// list.
//
// The kind picker is the same `CalendarKindFilter` the calendar uses, so the
// two planning surfaces are filtered the same way. It shows one kind at a time
// rather than stacking two scrolling lists — the nesting this workspace was
// built to remove.
//
// Both kinds are drag sources for the calendar pinned below.

import CoreData
import SwiftUI

struct LessonsAndWorkToScheduleView: View {
    let unscheduledWork: [CDWorkModel]
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    let attentionWorkIDs: Set<UUID>
    let sortMode: WorkAgendaSortMode
    let searchText: String
    let focusedPresentationID: UUID?
    let focusedWorkID: UUID?
    let onOpenWork: (CDWorkModel) -> Void
    let onMarkCompleted: (CDWorkModel) -> Void
    let onScheduleToday: (CDWorkModel) -> Void
    /// Children with a lesson on the calendar from today onward, computed once
    /// per refresh by the workspace rather than re-derived per row.
    let studentIDsWithUpcomingLessons: Set<UUID>

    @Environment(\.dependencies) private var dependencies
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Owned here so the waiting rail and the presentations it narrows share one
    /// student filter and one search.
    @State private var coordinator = PresentationsCoordinator()
    @State private var filterState = PresentationsFilterState()

    /// Presentations and work are planned in different motions — pick a lesson
    /// to give, versus give a stalled work item a date — so this starts on
    /// presentations rather than trying to interleave them.
    @SceneStorage("LessonsAndWork.toScheduleKind")
    private var kindRaw: String = CalendarKindFilter.presentations.rawValue

    private var kind: CalendarKindFilter {
        let resolved = CalendarKindFilter.resolved(rawValue: kindRaw)
        return resolved == .everything ? .presentations : resolved
    }

    private var kindBinding: Binding<CalendarKindFilter> {
        Binding(get: { kind }, set: { kindRaw = $0.rawValue })
    }

    private var filteredWork: [CDWorkModel] {
        let query = searchText.trimmed().lowercased()
        guard !query.isEmpty else { return unscheduledWork }
        return unscheduledWork.filter { work in
            let student = studentsByID[uuidString: work.studentID]
                .map(StudentFormatter.displayName(for:)) ?? ""
            let lesson = lessonsByID[uuidString: work.lessonID]?.name ?? ""
            return "\(work.title) \(student) \(lesson)".lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Plan", selection: kindBinding) {
                Text("Presentations").tag(CalendarKindFilter.presentations)
                Text(workTabTitle).tag(CalendarKindFilter.work)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch kind {
            case .work:
                workContent
            default:
                presentationPlanner
            }
        }
    }

    private var workTabTitle: String {
        unscheduledWork.isEmpty ? "Work" : "Work (\(unscheduledWork.count))"
    }

    @ViewBuilder
    private var workContent: some View {
        if filteredWork.isEmpty {
            ContentUnavailableView(
                searchText.trimmed().isEmpty ? "Every Work Item Has a Day" : "No Matching Work",
                systemImage: "calendar.badge.checkmark",
                description: Text(
                    searchText.trimmed().isEmpty
                        ? "Work with a due date or a scheduled check-in appears under Scheduled."
                        : "No unscheduled work matches this search."
                )
            )
        } else {
            OpenWorkGrid(
                works: filteredWork,
                lessonsByID: lessonsByID,
                studentsByID: studentsByID,
                attentionWorkIDs: attentionWorkIDs,
                sortMode: sortMode,
                focusedWorkID: focusedWorkID,
                onOpen: onOpenWork,
                onMarkCompleted: onMarkCompleted,
                onScheduleToday: onScheduleToday
            )
        }
    }

    /// Who has waited longest, beside what you could give them — so choosing a
    /// child and choosing a lesson never costs a screen change, and the
    /// calendar stays pinned below to drop onto.
    @ViewBuilder
    private var presentationPlanner: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            waitingStudentsRail
                .frame(width: WaitingStudentsRail.preferredWidth)
            Divider()
            presentations
                .frame(maxWidth: .infinity)
        }
        #else
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                waitingStudentsRail
                    .frame(width: WaitingStudentsRail.preferredWidth)
                Divider()
                presentations
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                // No room for a column on a phone, so the same list lies on its
                // side above the lessons rather than becoming another tab.
                WaitingStudentsStrip(
                    viewModel: dependencies.presentationsViewModel,
                    coordinator: coordinator,
                    filterState: filterState,
                    studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
                )
                Divider()
                presentations
            }
        }
        #endif
    }

    private var waitingStudentsRail: some View {
        WaitingStudentsRail(
            viewModel: dependencies.presentationsViewModel,
            coordinator: coordinator,
            filterState: filterState,
            studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
        )
    }

    private var presentations: some View {
        PresentationsView(
            embeddedSearchText: searchText,
            focusedPresentationID: focusedPresentationID,
            coordinator: coordinator,
            filterState: filterState
        )
    }
}
