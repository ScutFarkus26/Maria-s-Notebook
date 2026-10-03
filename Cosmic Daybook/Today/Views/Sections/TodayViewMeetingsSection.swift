// TodayViewMeetingsSection.swift
// The day's scheduled meetings, in a small section of their own after the
// lessons (hidden on a day with none), dragged into whatever order the day
// needs, plus the supporting functions
// (start/clear meeting, lesson plan resolution).

import SwiftUI
import CoreData
import OSLog

extension TodayView {

    // MARK: - Meetings Section

    @ViewBuilder
    var meetingsListSection: some View {
        if TodaySectionVisibility.showsMeetings(count: viewModel.scheduledMeetings.count) {
            Section {
                ForEach(viewModel.scheduledMeetings) { meeting in
                    meetingRow(meeting)
                        .id(meeting.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .onMove { source, destination in
                    viewModel.moveMeeting(from: source, to: destination)
                }
            } header: {
                sectionHeader("Meetings")
            }
        }
    }

    private func meetingRow(_ meeting: CDScheduledMeeting) -> some View {
        ScheduledMeetingListRow(
            studentName: meetingStudentName(for: meeting),
            onTap: { startMeeting(meeting) }
        )
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

    // MARK: - Helpers

    func meetingStudentName(for meeting: CDScheduledMeeting) -> String {
        let ids = meeting.allStudentIDs.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return "Student removed" }

        let names = ids.compactMap { viewModel.displayName(for: $0) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Student removed" }

        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names[0]), \(names[1]) + \(names.count - 2) more"
    }

    func startMeeting(_ meeting: CDScheduledMeeting) {
        guard let firstID = meeting.allStudentIDs.first.flatMap({ UUID(uuidString: $0) }),
              let meetingID = meeting.id else { return }
        selectedMeetingStudentID = firstID
        selectedMeetingID = meetingID
    }

    func clearScheduledMeeting(_ meeting: CDScheduledMeeting) {
        guard let meetingID = meeting.id else { return }
        MeetingScheduler.clearMeeting(id: meetingID, context: viewContext)
        viewModel.reload()
    }

    func lessonForPresentation(_ presentation: CDLessonAssignment) -> CDLesson? {
        viewModel.lessonsByID[presentation.resolvedLessonID]
    }

    func openLessonPlan(for presentation: CDLessonAssignment) {
        guard let lesson = lessonForPresentation(presentation) else { return }

        if let attachment = primaryLessonAttachment(for: lesson) {
            openLessonAttachment(attachment)
            return
        }

        if let relativePath = lesson.pagesFileRelativePath, !relativePath.isEmpty {
            do {
                let url = try LessonFileStorage.resolve(relativePath: relativePath)
                openLessonPlan(at: url)
                return
            } catch {
                Logger.app_.warning("Failed to resolve lesson plan path: \(error.localizedDescription)")
            }
        }

        guard
            let bookmark = lesson.pagesFileBookmark,
            let url = resolveLessonPlanBookmark(bookmark)
        else {
            return
        }

        openLessonPlan(at: url)
    }

    private func primaryLessonAttachment(for lesson: CDLesson) -> CDLessonAttachment? {
        guard let primaryID = lesson.primaryAttachmentIDUUID else { return nil }
        return LessonFileStorage.getAttachments(forLesson: lesson).first(where: { $0.id == primaryID })
    }

    private func openLessonAttachment(_ attachment: CDLessonAttachment) {
        if !attachment.fileRelativePath.isEmpty {
            do {
                let url = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
                openLessonPlan(at: url)
                return
            } catch {
                Logger.app_.warning("Failed to resolve primary lesson attachment path: \(error.localizedDescription)")
            }
        }

        guard
            let bookmark = attachment.fileBookmark,
            let url = resolveLessonPlanBookmark(bookmark)
        else {
            return
        }

        openLessonPlan(at: url)
    }

    private func resolveLessonPlanBookmark(_ bookmark: Data) -> URL? {
        do {
            let url = try SecurityScopedBookmark.resolve(bookmark).url
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            Logger.app_.warning("Failed to resolve lesson plan bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Opens the plan once its file is on this device (an iCloud file may
    /// still have to download; see `UbiquitousFile`).
    private func openLessonPlan(at url: URL) {
        Task {
            let url = await UbiquitousFile.localURL(for: url)
#if os(iOS)
            _ = await UIApplication.shared.open(url)
#elseif os(macOS)
            NSWorkspace.shared.open(url)
#endif
        }
    }
}
