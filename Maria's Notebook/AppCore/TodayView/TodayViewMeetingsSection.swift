// TodayViewMeetingsSection.swift
// Scheduled meetings section for TodayView

import SwiftUI
import SwiftData
import OSLog

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

    func meetingStudentName(for meeting: ScheduledMeeting) -> String {
        guard let studentID = meeting.studentIDUUID else { return "Unknown" }
        return viewModel.displayName(for: studentID)
    }

    func startMeeting(_ meeting: ScheduledMeeting) {
        guard let studentID = meeting.studentIDUUID else { return }
        selectedMeetingStudentID = studentID
        selectedMeetingID = meeting.id
    }

    func clearScheduledMeeting(_ meeting: ScheduledMeeting) {
        MeetingScheduler.clearMeeting(id: meeting.id, context: modelContext)
        viewModel.reload()
    }

    func lessonForPresentation(_ presentation: LessonAssignment) -> Lesson? {
        viewModel.lessonsByID[presentation.resolvedLessonID]
    }

    func lessonHasPlanDocument(_ lesson: Lesson?) -> Bool {
        guard let lesson else { return false }
        if primaryLessonAttachment(for: lesson) != nil {
            return true
        }
        if let relativePath = lesson.pagesFileRelativePath, !relativePath.isEmpty {
            return true
        }
        return lesson.pagesFileBookmark != nil
    }

    func openLessonPlan(for presentation: LessonAssignment) {
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

    private func primaryLessonAttachment(for lesson: Lesson) -> LessonAttachment? {
        guard let primaryID = lesson.primaryAttachmentIDUUID else { return nil }
        return LessonFileStorage.getAttachments(forLesson: lesson).first(where: { $0.id == primaryID })
    }

    private func openLessonAttachment(_ attachment: LessonAttachment) {
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
        var stale = false

        do {
#if os(macOS)
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
#else
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            Logger.app_.warning("Failed to resolve lesson plan bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    private func openLessonPlan(at url: URL) {
#if os(iOS)
        UIApplication.shared.open(url)
#elseif os(macOS)
        NSWorkspace.shared.open(url)
#endif
    }
}
