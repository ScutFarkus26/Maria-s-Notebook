// TodayViewMeetingsSection.swift
// Scheduled meetings section for TodayView

import SwiftUI
import SwiftData

extension TodayView {

    // MARK: - Meetings Section

    var meetingsListSection: some View {
        Section {
            if viewModel.scheduledMeetings.isEmpty {
                emptyStateText("No meetings scheduled")
            } else {
                ForEach(viewModel.scheduledMeetings) { meeting in
                    let name = meetingStudentName(for: meeting)
                    ScheduledMeetingListRow(studentName: name) {
                        startMeeting(meeting)
                    }
                    .id(meeting.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
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
            }
        } header: {
            meetingsSectionHeader
        }
    }

    @ViewBuilder
    var meetingsSectionHeader: some View {
        HStack {
            Text("Meetings")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.scheduledMeetings.count
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

    private func meetingStudentName(for meeting: ScheduledMeeting) -> String {
        guard let studentID = meeting.studentIDUUID else { return "Unknown" }
        return viewModel.displayName(for: studentID)
    }

    private func startMeeting(_ meeting: ScheduledMeeting) {
        guard let studentID = meeting.studentIDUUID else { return }
        selectedMeetingStudentID = studentID
        selectedMeetingID = meeting.id
    }

    func clearScheduledMeeting(_ meeting: ScheduledMeeting) {
        MeetingScheduler.clearMeeting(id: meeting.id, context: modelContext)
        viewModel.reload()
    }
}
