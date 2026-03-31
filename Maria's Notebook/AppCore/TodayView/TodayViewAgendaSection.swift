// TodayViewAgendaSection.swift
// Agenda, Presented Lessons, Checked Work, and Completed sections for TodayView
// Extracted for maintainability

import SwiftUI
import CoreData

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
        case .lesson(let sl):
            agendaLessonRow(sl)

        case .meeting(let meeting):
            agendaMeetingRow(meeting)

        case .scheduledWork(let scheduled):
            ScheduledWorkListRow(
                item: scheduled,
                studentName: resolveStudentName(for: scheduled.work),
                lessonName: resolveLessonName(for: scheduled.work),
                onTap: {
                    selectedWorkID = scheduled.work.id
                }
            )

        case .followUp(let followUp):
            FollowUpWorkListRow(
                item: followUp,
                studentName: resolveStudentName(for: followUp.work),
                lessonName: resolveLessonName(for: followUp.work),
                onTap: {
                    selectedWorkID = followUp.work.id
                }
            )

        case .groupedScheduledWork(let items):
            GroupedScheduledWorkListRow(
                items: items,
                studentNames: items.map { resolveStudentName(for: $0.work) },
                lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
                isFlexible: items.first?.work.checkInStyle == .flexible,
                onTap: { workID in
                    selectedWorkID = workID
                }
            )

        case .groupedFollowUp(let items):
            GroupedFollowUpWorkListRow(
                items: items,
                studentNames: items.map { resolveStudentName(for: $0.work) },
                lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
                isFlexible: items.first?.work.checkInStyle == .flexible,
                onTap: { workID in
                    selectedWorkID = workID
                }
            )
        }
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

    // MARK: - Completed Section

    var completedListSection: some View {
        Section {
            if viewModel.completedWork.isEmpty {
                emptyStateText("No completions yet")
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
            sectionHeader("Completed")
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
