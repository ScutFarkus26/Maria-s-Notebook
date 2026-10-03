// TodayViewAgendaSection.swift
// The Lessons section for TodayView — the day's lessons in one reorderable
// list, its first lesson not yet given drawn as the Next card
// (TodayViewNextCard.swift). Scheduled meetings and quiet work have sections
// of their own (TodayViewMeetingsSection.swift,
// TodayViewGoneQuietSection.swift). The header and the absent-children move
// live in TodayView+AbsentMove.swift. The retrospective halves it used to
// carry (Lessons Presented, Work Checked) live in
// TodayViewDoneTodaySection.swift, beside the disclosure that shows them.

import SwiftUI
import CoreData
import OSLog

// MARK: - TodayView Agenda Section Extension

extension TodayView {

    // MARK: - Unified Agenda Section

    var agendaListSection: some View {
        // Decided once per draw: the lesson drawn as the Next card, if any.
        let nextLessonID: UUID? = nextAgendaItem.flatMap { item in
            if case .lesson = item { return item.id }
            return nil
        }
        return Section {
            nextCheckInCard
            if viewModel.agendaItems.isEmpty {
                // The agenda never hides: on macOS it is a whole column, and
                // "nothing planned" is the answer the guide came for.
                emptyStateText("Nothing scheduled for today.")
            } else {
                ForEach(viewModel.agendaItems) { item in
                    agendaRow(for: item, isNext: item.id == nextLessonID)
                        .id(item.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .onMove { source, destination in
                    viewModel.moveAgendaItem(from: source, to: destination)
                }
            }
        } header: {
            lessonsSectionHeader
        }
    }

    @ViewBuilder
    func agendaRow(for item: AgendaItem, isNext: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            agendaTypeIndicator(for: item)
            agendaRowContent(for: item, isNext: isNext)
        }
        .todayNextHighlight(isNext)
    }

    @ViewBuilder
    func agendaTypeIndicator(for item: AgendaItem) -> some View {
        let (icon, color): (String, Color) = {
            switch item {
            case .lesson:
                return ("book.fill", .blue)
            case .scheduledWork:
                return ("clock.fill", .orange)
            case .followUp:
                return ("arrow.uturn.left.circle.fill", .purple)
            case .groupedScheduledWork:
                return ("person.3.fill", .orange)
            case .groupedFollowUp:
                return ("person.3.fill", .purple)
            }
        }()

        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(color.opacity(UIConstants.OpacityConstants.heavy))
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    func agendaRowContent(for item: AgendaItem, isNext: Bool) -> some View {
        switch item {
        case .lesson(let sl): agendaLessonRow(sl, isNext: isNext)
        case .scheduledWork(let scheduled): agendaScheduledWorkRow(scheduled)
        case .groupedScheduledWork(let items): agendaGroupedScheduledWorkRow(items)
        case .followUp, .groupedFollowUp: goneQuietRow(for: item, checkInDay: nextSchoolDaySync(after: Date()))
        }
    }

    @ViewBuilder
    private func agendaScheduledWorkRow(_ scheduled: ScheduledWorkItem) -> some View {
        ScheduledWorkListRow(
            item: scheduled,
            studentName: resolveStudentName(for: scheduled.work),
            lessonName: resolveLessonName(for: scheduled.work),
            onTap: { selectedWorkID = scheduled.work.id }
        )
        .contextMenu {
            Button {
                selectedWorkID = scheduled.work.id
            } label: {
                Label("Open Detail", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                bumpCheckInToTomorrow(scheduled.checkIn)
            } label: {
                Label("Bump to \(bumpTargetTitle)", systemImage: "calendar.badge.plus")
            }
            Button {
                quickNoteAboutWork(scheduled.work)
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
            }
            Divider()
            WorkLogStatusMenu(targets: [scheduled.work]) { rows, status in
                logWorkStatus(rows, as: status)
            }
        }
    }

    @ViewBuilder
    private func agendaGroupedScheduledWorkRow(_ items: [ScheduledWorkItem]) -> some View {
        GroupedScheduledWorkListRow(
            items: items,
            studentNames: items.map { resolveStudentName(for: $0.work) },
            lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
            isFlexible: items.first?.work.checkInStyle == .flexible,
            onTap: { workID in selectedWorkID = workID }
        )
    }

    @ViewBuilder
    private func agendaLessonRow(_ sl: CDLessonAssignment, isNext: Bool) -> some View {
        // Decided once per reload (TodayLessonsLoader.lessonIDsWithPlan).
        let hasPlan = viewModel.lessonIDsWithPlan.contains(sl.resolvedLessonID)
        let attendance = TodayLessonAttendance(
            studentIDs: sl.resolvedStudentIDs,
            absent: viewModel.absentStudentIDs,
            here: viewModel.hereStudentIDs
        )
        let movesAbsent = attendance.hasAbsent && !sl.isPresented
        LessonListRow(
            lessonName: nameForLesson(sl.resolvedLessonID),
            children: lessonChips(for: sl, absent: viewModel.absentStudentIDs),
            hereText: attendance.hereText(attendanceTaken: viewModel.attendanceTaken),
            isPresented: sl.isPresented,
            trailingAccessorySystemName: hasPlan ? "doc.richtext" : nil,
            trailingAccessoryLabel: "Open lesson plan",
            onTrailingAccessoryTap: hasPlan ? {
                openLessonPlan(for: sl)
            } : nil,
            onMoveAbsent: movesAbsent ? { moveAbsentToTomorrow(from: [sl]) } : nil,
            moveAbsentTitle: "Move absent to \(bumpTargetName)",
            onPresent: isNext ? { startNextAgendaItem(.lesson(sl)) } : nil,
            presentShortcut: nextCardShortcut
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedLessonAssignment = sl
        }
        .contextMenu {
            if !sl.isPresented {
                Button {
                    markLessonPresented(sl)
                } label: {
                    Label("Mark Presented Now", systemImage: "checkmark.circle")
                }
            }
            Button {
                bumpLessonToTomorrow(sl)
            } label: {
                Label("Bump to \(bumpTargetTitle)", systemImage: "calendar.badge.plus")
            }
            if movesAbsent {
                Button {
                    moveAbsentToTomorrow(from: [sl])
                } label: {
                    Label("Move Absent Children to \(bumpTargetTitle)", systemImage: "person.badge.clock")
                }
            }
            Button {
                quickNoteAboutLesson(sl)
            } label: {
                Label("Add Note About This Lesson", systemImage: "square.and.pencil")
            }
        }
    }

    /// Records today for the children who were there; an absent child stays
    /// on the plan (`TodayMarkPresented`).
    func markLessonPresented(_ sl: CDLessonAssignment) {
        do {
            let result = try TodayMarkPresented.record(
                sl, context: viewContext, saveCoordinator: saveCoordinator
            )
            viewModel.reload()
            toast(TodayMarkPresented.message(keptOnPlan: result.keptOnPlan.map { displayNameForID($0) }))
        } catch {
            Logger.app_.warning("Failed to mark lesson presented: \(error.localizedDescription)")
            toast(error.localizedDescription)
        }
    }

    func bumpLessonToTomorrow(_ sl: CDLessonAssignment) {
        // The next school day after the day shown (`bumpTargetDay`), not after
        // the item's own date — adding a day to an overdue item's old date
        // would leave it overdue.
        guard let tomorrow = bumpTargetDay() else { return }
        // A bump expresses a day, so it lands at the start of the morning
        // rather than ahead of everything already planned.
        sl.schedule(onDay: tomorrow)
        let name = bumpTargetName
        if saveCoordinator.save(viewContext, reason: "Bump lesson to tomorrow") {
            viewModel.reload()
            toast("Bumped to \(name)")
        }
    }

    func quickNoteAboutLesson(_ sl: CDLessonAssignment) {
        activeSheet = .quickNote(
            studentIDs: sl.resolvedStudentIDs.isEmpty ? nil : Set(sl.resolvedStudentIDs)
        )
    }

    func bumpCheckInToTomorrow(_ checkIn: CDWorkCheckIn) {
        // The next school day after the day shown (`bumpTargetDay`), not after
        // the check-in's own date — adding a day to a 5-day-old check-in moved
        // it to 4 days ago, still overdue. Keep the original time of day so
        // intra-day ordering stays stable.
        let base = checkIn.date ?? viewModel.date
        guard let startOfTomorrow = bumpTargetDay() else { return }
        let name = bumpTargetName
        let time = calendar.dateComponents([.hour, .minute, .second], from: base)
        checkIn.date = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: startOfTomorrow
        ) ?? startOfTomorrow
        if saveCoordinator.save(viewContext, reason: "Bump check-in to tomorrow") {
            viewModel.reload()
            toast("Bumped to \(name)")
        }
    }

    /// The same write as the Scheduled strip's menu: today's check-in is
    /// marked done and the row leaves the agenda on reload.
    func logWorkStatus(_ rows: [CDWorkModel], as status: WorkStatus) {
        do {
            try WorkLogService.log(
                rows.map { WorkLogService.Entry(work: $0, status: status) },
                context: viewContext
            )
        } catch {
            toast(error.localizedDescription)
            return
        }
        viewModel.reload()
        toast("Logged as \(status.displayName)")
    }

    func quickNoteAboutWork(_ work: CDWorkModel) {
        let studentIDs: Set<UUID>? = UUID(uuidString: work.studentID).map { [$0] }
        activeSheet = .quickNote(studentIDs: studentIDs)
    }

    // MARK: - Helper Views

    @ViewBuilder
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    @ViewBuilder
    func emptyStateText(_ text: String) -> some View {
        Self.emptyStateLabel(text)
    }

    static func emptyStateLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.ScaledFont.callout)
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}
