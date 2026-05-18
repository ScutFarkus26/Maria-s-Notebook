// TodayViewAgendaSection.swift
// Agenda, Presented Lessons, Checked Work, and Completed sections for TodayView
// Extracted for maintainability

import SwiftUI
import CoreData
import OSLog

// MARK: - TodayView Agenda Section Extension

extension TodayView {

    // MARK: - Presented Lessons Section

    var presentedLessonsListSection: some View {
        Section {
            let presented = viewModel.todaysLessons.filter(\.isPresented)
            if presented.isEmpty {
                emptyStateText("No lessons presented yet")
            } else {
                ForEach(presented) { sl in
                    let lesson = lessonForPresentation(sl)
                    LessonListRow(
                        lessonName: nameForLesson(sl.resolvedLessonID),
                        studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                        isPresented: true,
                        trailingAccessorySystemName: lessonHasPlanDocument(lesson) ? "doc.richtext" : nil,
                        trailingAccessoryLabel: "Open lesson plan",
                        onTrailingAccessoryTap: lessonHasPlanDocument(lesson) ? {
                            openLessonPlan(for: sl)
                        } : nil
                    )
                    .id(sl.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLessonAssignment = sl
                    }
                }
            }
        } header: {
            presentedLessonsSectionHeader
        }
    }

    @ViewBuilder
    var presentedLessonsSectionHeader: some View {
        HStack {
            Text("Lessons Presented")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.todaysLessons.filter(\.isPresented).count
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Checked Work Section

    var checkedWorkListSection: some View {
        Section {
            if viewModel.completedWork.isEmpty {
                emptyStateText("No work checked yet")
            } else {
                ForEach(viewModel.completedWork) { work in
                    CompletionListRow(
                        studentName: resolveStudentName(for: work),
                        lessonName: resolveLessonName(for: work),
                        work: work
                    )
                    .id(work.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkID = work.id
                    }
                }
            }
        } header: {
            checkedWorkSectionHeader
        }
    }

    @ViewBuilder
    var checkedWorkSectionHeader: some View {
        HStack {
            Text("Work Checked")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.completedWork.count
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Unified Agenda Section

    var agendaListSection: some View {
        Section {
            if viewModel.agendaItems.isEmpty {
                emptyStateText("No lessons or work items scheduled")
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
            try viewContext.save()
            viewModel.reload()
            toast("Marked presented")
        } catch {
            Logger.app_.warning("Failed to mark lesson presented: \(error.localizedDescription)")
        }
    }

    func bumpLessonToTomorrow(_ sl: CDLessonAssignment) {
        let base = sl.scheduledFor ?? viewModel.date
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: base) else { return }
        sl.schedule(for: tomorrow)
        do {
            try viewContext.save()
            viewModel.reload()
            toast("Bumped to tomorrow")
        } catch {
            Logger.app_.warning("Failed to bump lesson: \(error.localizedDescription)")
        }
    }

    func quickNoteAboutLesson(_ sl: CDLessonAssignment) {
        pendingNoteStudentIDs = sl.resolvedStudentIDs.isEmpty
            ? nil
            : Set(sl.resolvedStudentIDs)
        isShowingQuickNote = true
    }

    func bumpCheckInToTomorrow(_ checkIn: CDWorkCheckIn) {
        let base = checkIn.date ?? viewModel.date
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: base) else { return }
        checkIn.date = tomorrow
        do {
            try viewContext.save()
            viewModel.reload()
            toast("Bumped to tomorrow")
        } catch {
            Logger.app_.warning("Failed to bump check-in: \(error.localizedDescription)")
        }
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
