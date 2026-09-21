// TodayViewAgendaSection.swift
// The unified Agenda section for TodayView — the day's lessons and work in one
// reorderable list. The retrospective halves it used to carry (Lessons
// Presented, Work Checked) live in TodayViewDoneTodaySection.swift, beside the
// disclosure that shows them.
// Extracted for maintainability

import SwiftUI
import CoreData
import OSLog

// MARK: - TodayView Agenda Section Extension

extension TodayView {

    // MARK: - Unified Agenda Section

    var agendaListSection: some View {
        Section {
            if viewModel.agendaItems.isEmpty {
                // The agenda never hides: on macOS it is a whole column, and
                // "nothing planned" is the answer the guide came for.
                emptyStateText("Nothing scheduled for today.")
            } else {
                ForEach(viewModel.agendaItems) { item in
                    agendaRow(for: item)
                        .id(item.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .onMove { source, destination in
                    viewModel.moveAgendaItem(from: source, to: destination)
                }
            }
        } header: {
            sectionHeader("Agenda")
        }
    }

    @ViewBuilder
    func agendaRow(for item: AgendaItem) -> some View {
        HStack(spacing: 10) {
            agendaTypeIndicator(for: item)
            agendaRowContent(for: item)
        }
    }

    @ViewBuilder
    func agendaTypeIndicator(for item: AgendaItem) -> some View {
        let (icon, color): (String, Color) = {
            switch item {
            case .lesson:
                return ("book.fill", .blue)
            case .meeting:
                return ("person.crop.circle.badge.clock", .teal)
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
    func agendaRowContent(for item: AgendaItem) -> some View {
        switch item {
        case .lesson(let sl): agendaLessonRow(sl)
        case .meeting(let meeting): agendaMeetingRow(meeting)
        case .scheduledWork(let scheduled): agendaScheduledWorkRow(scheduled)
        case .followUp(let followUp): agendaFollowUpRow(followUp)
        case .groupedScheduledWork(let items): agendaGroupedScheduledWorkRow(items)
        case .groupedFollowUp(let items): agendaGroupedFollowUpRow(items)
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
                Label("Bump to Tomorrow", systemImage: "calendar.badge.plus")
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
    private func agendaFollowUpRow(_ followUp: FollowUpWorkItem) -> some View {
        FollowUpWorkListRow(
            item: followUp,
            studentName: resolveStudentName(for: followUp.work),
            lessonName: resolveLessonName(for: followUp.work),
            onTap: { selectedWorkID = followUp.work.id }
        )
        .contextMenu {
            Button {
                selectedWorkID = followUp.work.id
            } label: {
                Label("Open Detail", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                quickNoteAboutWork(followUp.work)
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
            }
            Divider()
            WorkLogStatusMenu(targets: [followUp.work]) { rows, status in
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
    private func agendaGroupedFollowUpRow(_ items: [FollowUpWorkItem]) -> some View {
        GroupedFollowUpWorkListRow(
            items: items,
            studentNames: items.map { resolveStudentName(for: $0.work) },
            lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
            isFlexible: items.first?.work.checkInStyle == .flexible,
            onTap: { workID in selectedWorkID = workID }
        )
    }

    @ViewBuilder
    private func agendaLessonRow(_ sl: CDLessonAssignment) -> some View {
        let lesson = lessonForPresentation(sl)
        LessonListRow(
            lessonName: nameForLesson(sl.resolvedLessonID),
            studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
            isPresented: sl.isPresented,
            trailingAccessorySystemName: lessonHasPlanDocument(lesson) ? "doc.richtext" : nil,
            trailingAccessoryLabel: "Open lesson plan",
            onTrailingAccessoryTap: lessonHasPlanDocument(lesson) ? {
                openLessonPlan(for: sl)
            } : nil
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
                Label("Bump to Tomorrow", systemImage: "calendar.badge.plus")
            }
            Button {
                quickNoteAboutLesson(sl)
            } label: {
                Label("Add Note About This Lesson", systemImage: "square.and.pencil")
            }
        }
    }

    func markLessonPresented(_ sl: CDLessonAssignment) {
        do {
            _ = try LifecycleService.recordPresentation(
                from: sl,
                presentedAt: Date(),
                modelContext: viewContext
            )
            if saveCoordinator.save(viewContext, reason: "Mark lesson presented") {
                viewModel.reload()
                toast("Marked presented")
            }
        } catch {
            Logger.app_.warning("Failed to mark lesson presented: \(error.localizedDescription)")
        }
    }

    func bumpLessonToTomorrow(_ sl: CDLessonAssignment) {
        // "Tomorrow" is relative to today, not the item's own date — adding a day
        // to an overdue item's old date would leave it in the past, still overdue.
        guard let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())
        ) else { return }
        // A bump expresses a day, so it lands at the start of the morning
        // rather than ahead of everything already planned.
        sl.schedule(onDay: tomorrow)
        if saveCoordinator.save(viewContext, reason: "Bump lesson to tomorrow") {
            viewModel.reload()
            toast("Bumped to tomorrow")
        }
    }

    func quickNoteAboutLesson(_ sl: CDLessonAssignment) {
        pendingNoteStudentIDs = sl.resolvedStudentIDs.isEmpty
            ? nil
            : Set(sl.resolvedStudentIDs)
        isShowingQuickNote = true
    }

    func bumpCheckInToTomorrow(_ checkIn: CDWorkCheckIn) {
        // "Tomorrow" is relative to today, not the check-in's own date — adding a
        // day to a 5-day-old check-in moved it to 4 days ago, still overdue.
        // Keep the original time of day so intra-day ordering stays stable.
        let base = checkIn.date ?? viewModel.date
        guard let startOfTomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())
        ) else { return }
        let time = calendar.dateComponents([.hour, .minute, .second], from: base)
        checkIn.date = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: startOfTomorrow
        ) ?? startOfTomorrow
        if saveCoordinator.save(viewContext, reason: "Bump check-in to tomorrow") {
            viewModel.reload()
            toast("Bumped to tomorrow")
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
        if let studentID = UUID(uuidString: work.studentID) {
            pendingNoteStudentIDs = [studentID]
        } else {
            pendingNoteStudentIDs = nil
        }
        isShowingQuickNote = true
    }

    @ViewBuilder
    private func agendaMeetingRow(_ meeting: CDScheduledMeeting) -> some View {
        ScheduledMeetingListRow(
            studentName: meetingStudentName(for: meeting),
            showsLeadingIcon: false,
            onTap: nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            startMeeting(meeting)
        }
        .contextMenu {
            Button {
                startMeeting(meeting)
            } label: {
                Label("Start Meeting", systemImage: "play.fill")
            }

            Divider()

            Button(role: .destructive) {
                clearScheduledMeeting(meeting)
            } label: {
                Label("Remove", systemImage: "calendar.badge.minus")
            }
        }
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
        Text(text)
            .font(AppTheme.ScaledFont.callout)
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}
