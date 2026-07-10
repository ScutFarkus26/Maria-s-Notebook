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

    var doneTodayListSection: some View {
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
