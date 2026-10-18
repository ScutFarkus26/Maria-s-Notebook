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
        TodayMeetingRow(
            names: meetingStudentName(for: meeting),
            children: meetingChildren(for: meeting),
            onStart: { startMeeting(meeting, with: $0) },
            onRemove: { clearScheduledMeeting(meeting) }
        )
    }

    // MARK: - Helpers

    func meetingStudentName(for meeting: CDScheduledMeeting) -> String {
        TodayMeetingRows.names(
            for: meeting.allStudentIDs.compactMap { UUID(uuidString: $0) },
            knownStudents: viewModel.meetingStudentsByID
        )
    }

    /// The children booked into the meeting, by short name, for the pick a
    /// group booking shows. A child no longer in the notebook is left out;
    /// when nobody is left, the first one opens (the session says she's gone).
    func meetingChildren(for meeting: CDScheduledMeeting) -> [TodayMeetingRow.Child] {
        let ids = meeting.allStudentIDs.compactMap { UUID(uuidString: $0) }
        let known = ids.compactMap { id in
            viewModel.meetingStudentsByID[id].map { TodayMeetingRow.Child(id: id, name: $0.shortName) }
        }
        if known.isEmpty, let first = ids.first {
            return [TodayMeetingRow.Child(id: first, name: "")]
        }
        return known
    }

    /// Opens the meeting with one child. Completing it takes only her off a
    /// group booking (`MeetingScheduler.clearMeeting(id:completedFor:)`).
    func startMeeting(_ meeting: CDScheduledMeeting, with studentID: UUID) {
        guard let meetingID = meeting.id else { return }
        selectedMeetingStudentID = studentID
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

    /// The bookmarked plan. Access isn't started here: `openLessonPlan` holds
    /// it while the plan is open (it used to start on every tap and never
    /// stop; review of the 2026-10-17 fixes, a2 #7).
    private func resolveLessonPlanBookmark(_ bookmark: Data) -> URL? {
        do {
            return try SecurityScopedBookmark.resolve(bookmark).url
        } catch {
            Logger.app_.warning("Failed to resolve lesson plan bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Opens the plan once its file is on this device (an iCloud file may
    /// still have to download; see `UbiquitousFile`). On iPhone and iPad,
    /// where `UIApplication.open` can't open a file, a Pages plan goes to the
    /// share sheet (where Pages offers itself) and any other file to Quick
    /// Look; `DocumentPresenter` holds access until it closes (#22's last
    /// button, review a2 #7).
    private func openLessonPlan(at url: URL) {
        Task {
#if os(iOS)
            let style: DocumentPresenter.Style = url.pathExtension.lowercased() == "pages" ? .share : .preview
            if let message = await DocumentPresenter.open(url, as: style).message {
                ToastService.shared.showError(message)
            }
#elseif os(macOS)
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.open(await UbiquitousFile.localURL(for: url))
#endif
        }
    }
}

// MARK: - Meeting Row

/// One booking on Today. Tapping a group booking asks which child to meet
/// first, since the meeting is held with one child at a time; the others
/// keep the booking until they have met (bug hunt 2026-10-11, #27).
struct TodayMeetingRow: View {
    struct Child: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    let names: String
    let children: [Child]
    let onStart: (UUID) -> Void
    let onRemove: () -> Void

    @State private var isPickingChild = false

    var body: some View {
        ScheduledMeetingListRow(studentName: names, onTap: start)
            .contextMenu {
                Button(action: start) {
                    Label("Start Meeting", systemImage: "play.fill")
                }

                Divider()

                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "calendar.badge.minus")
                }
            }
            .confirmationDialog("Who are you meeting with?", isPresented: $isPickingChild, titleVisibility: .visible) {
                ForEach(children) { child in
                    Button(child.name) { onStart(child.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Meet one child at a time. The others stay booked until they have met.")
            }
    }

    private func start() {
        if children.count > 1 {
            isPickingChild = true
        } else if let only = children.first {
            onStart(only.id)
        }
    }
}
