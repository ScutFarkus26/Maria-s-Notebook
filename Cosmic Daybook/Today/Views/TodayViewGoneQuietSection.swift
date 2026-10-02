// TodayViewGoneQuietSection.swift
// Gone quiet: open work nobody has touched in 10+ days, in its own section
// after Meetings (hidden when there is none).
//
// It used to ride in the Lessons list as reorderable rows. Its own section
// lists it most quiet first instead, so drag-to-reorder is gone for these
// rows: an order the guide set would only last until the ages changed. The
// header says how many there really are ("See all 23", the true count, not
// the 15 rows kept) and opens the work in Lessons & Work. On the Mac it
// replaces Right Now's "Open work to check".

import SwiftUI
import CoreData

extension TodayView {

    // MARK: - Section

    @ViewBuilder
    var goneQuietListSection: some View {
        if TodaySectionVisibility.showsGoneQuiet(count: viewModel.goneQuietItems.count) {
            // Decided once per draw: where Schedule check-in's picker opens.
            let checkInDay = nextSchoolDaySync(after: Date())
            Section {
                ForEach(viewModel.goneQuietItems) { item in
                    goneQuietRow(for: item, checkInDay: checkInDay)
                        .id(item.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            } header: {
                goneQuietHeader
            }
        }
    }

    private var goneQuietHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader(TodayGoneQuiet.title)
                Spacer()
                Button(TodayGoneQuiet.seeAllText(totalCount: viewModel.staleTotalCount)) {
                    appRouter.navigateToLessonsAndWork(.attention, preferredKind: .work)
                }
                .buttonStyle(.borderless)
                .font(AppTheme.ScaledFont.caption)
                .textCase(nil)
                .help("Opens the work waiting on you in Lessons & Work")
            }
            Text(TodayGoneQuiet.subtitle)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    // MARK: - Rows

    /// A Gone quiet row. The agenda's row switch reaches the quiet cases
    /// through here too, though the agenda no longer carries them; Gone
    /// quiet carries nothing else.
    @ViewBuilder
    func goneQuietRow(for item: AgendaItem, checkInDay: Date) -> some View {
        switch item {
        case .followUp(let followUp):
            quietWorkRow(followUp, checkInDay: checkInDay)
        case .groupedFollowUp(let items):
            groupedQuietWorkRow(items, checkInDay: checkInDay)
        case .lesson, .scheduledWork, .groupedScheduledWork:
            EmptyView()
        }
    }

    private func quietWorkRow(_ followUp: FollowUpWorkItem, checkInDay: Date) -> some View {
        FollowUpWorkListRow(
            item: followUp,
            title: resolveLessonName(for: followUp.work),
            children: [quietWorkChip(for: followUp.work)],
            linkedTodos: followUp.work.id.flatMap { viewModel.linkedTodos.byWork[$0] },
            checkInDay: checkInDay,
            onTap: { selectedWorkID = followUp.work.id },
            onSchedule: { day in scheduleQuietWork([followUp.work], on: day) }
        )
        .contextMenu {
            quietWorkMenu(for: [followUp.work])
        }
    }

    private func groupedQuietWorkRow(_ items: [FollowUpWorkItem], checkInDay: Date) -> some View {
        let works = items.map(\.work)
        return GroupedFollowUpWorkListRow(
            items: items,
            title: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
            children: works.map { quietWorkChip(for: $0) },
            linkedTodos: viewModel.linkedTodos.rowTodos(for: works.compactMap(\.id), calendar: calendar),
            isFlexible: items.first?.work.checkInStyle == .flexible,
            checkInDay: checkInDay,
            onTap: { workID in selectedWorkID = workID },
            onSchedule: { day in scheduleQuietWork(works, on: day) }
        )
        .contextMenu {
            quietWorkMenu(for: works)
        }
    }

    @ViewBuilder
    private func quietWorkMenu(for works: [CDWorkModel]) -> some View {
        if works.count == 1, let work = works.first {
            Button {
                selectedWorkID = work.id
            } label: {
                Label("Open Detail", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                quickNoteAboutWork(work)
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
            }
            Divider()
        }
        WorkLogStatusMenu(targets: works) { rows, status in
            logWorkStatus(rows, as: status)
        }
    }

    /// The work's child as a chip, struck through when absent today.
    private func quietWorkChip(for work: CDWorkModel) -> TodayStudentChips.Chip {
        let studentID = UUID(uuidString: work.studentID)
        return TodayStudentChips.Chip(
            id: studentID ?? work.id ?? UUID(),
            name: resolveStudentName(for: work),
            isAbsent: studentID.map(viewModel.absentStudentIDs.contains) ?? false
        )
    }

    // MARK: - Scheduling

    func scheduleQuietWork(_ works: [CDWorkModel], on day: Date) {
        TodayCheckInScheduler.schedule(works, on: day, in: viewContext)
        guard saveCoordinator.save(viewContext, reason: "Schedule work check-in") else { return }
        viewModel.reload()
        toast("Check-in on \(DateFormatters.weekdayAndDate.string(from: day))")
    }
}
