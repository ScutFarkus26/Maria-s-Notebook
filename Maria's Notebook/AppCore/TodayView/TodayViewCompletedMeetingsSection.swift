// TodayViewCompletedMeetingsSection.swift
// Completed meetings section for TodayView (left column)

import SwiftUI
import SwiftData

extension TodayView {

    // MARK: - Completed Meetings Section

    var completedMeetingsListSection: some View {
        Section {
            if viewModel.completedMeetings.isEmpty {
                emptyStateText("No meetings completed yet")
            } else {
                ForEach(viewModel.completedMeetings) { meeting in
                    let name = completedMeetingStudentName(for: meeting)
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 14))
                            .foregroundStyle(.teal.opacity(0.6))
                            .frame(width: 20)
                        Text(name)
                            .font(AppTheme.ScaledFont.callout)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Completed meeting with \(name)")
                    .id(meeting.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
        } header: {
            completedMeetingsSectionHeader
        }
    }

    @ViewBuilder
    var completedMeetingsSectionHeader: some View {
        HStack {
            Text("Completed Meetings")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.completedMeetings.count
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    func completedMeetingStudentName(for meeting: StudentMeeting) -> String {
        guard let studentID = meeting.studentIDUUID else { return "Unknown" }
        return viewModel.displayName(for: studentID)
    }
}
