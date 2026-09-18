// TodayViewDoneTodaySection.swift
// Collapsed retrospective disclosure — rolls up Lessons Presented + Work Checked +
// Completed Meetings into one optional section so they don't crowd the live agenda.

import SwiftUI

extension TodayView {

    /// Total of completed items shown when the disclosure is collapsed.
    var doneTodayTotalCount: Int {
        let presented = viewModel.todaysLessons.filter(\.isPresented).count
        return presented + viewModel.completedWork.count + viewModel.completedMeetings.count
    }

    /// A day with nothing finished on it yet has no retrospective to offer.
    @ViewBuilder
    var doneTodayListSection: some View {
        if TodaySectionVisibility.showsDoneToday(total: doneTodayTotalCount) {
            doneTodaySection
        }
    }

    private var doneTodaySection: some View {
        Section {
            if isDoneTodayExpanded {
                if viewModel.todaysLessons.contains(where: \.isPresented) {
                    presentedLessonsListSection
                }
                if !viewModel.completedWork.isEmpty {
                    checkedWorkListSection
                }
                if !viewModel.completedMeetings.isEmpty {
                    completedMeetingsListSection
                }
            }
        } header: {
            doneTodaySectionHeader
        }
    }

    @ViewBuilder
    var doneTodaySectionHeader: some View {
        Button {
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                isDoneTodayExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Done so far today")
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                if doneTodayTotalCount > 0 {
                    Text("\(doneTodayTotalCount)")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(UIConstants.OpacityConstants.medium))
                        )
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isDoneTodayExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The sections the disclosure reveals
//
// Moved here from TodayViewAgendaSection.swift: "Lessons Presented" and "Work
// Checked" are only ever drawn inside the disclosure above, and the agenda
// file was over the 400-line limit.

extension TodayView {

    // MARK: - Presented Lessons Section

    var presentedLessonsListSection: some View {
        // Compute once; count forwarded to the header to avoid a second filter pass.
        let presented = viewModel.todaysLessons.filter(\.isPresented)
        return Section {
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
            presentedLessonsSectionHeader(count: presented.count)
        }
    }

    @ViewBuilder
    func presentedLessonsSectionHeader(count: Int) -> some View {
        HStack {
            Text("Lessons Presented")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
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

}
