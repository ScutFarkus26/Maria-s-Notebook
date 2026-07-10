// TodayViewRightNowSection.swift
// Right Now hero — what's next on the agenda and a count of work waiting to be
// checked. Glance-and-go dashboard at the top of Today.

import SwiftUI
import CoreData

extension TodayView {

    var rightNowListSection: some View {
        Section {
            rightNowContent
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        } header: {
            sectionHeader("Right Now")
        }
    }

    @ViewBuilder
    private var rightNowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            rightNowNext
            rightNowOpenWork
            rightNowEmpty
        }
    }

    @ViewBuilder
    private var rightNowNext: some View {
        if let next = nextAgendaItem {
            nextUpRow(item: next)
        }
    }

    @ViewBuilder
    private var rightNowOpenWork: some View {
        if openWorkToCheckCount > 0 {
            openWorkRow(count: openWorkToCheckCount)
        }
    }

    private var hasNoRightNowContent: Bool {
        let hasNext = nextAgendaItem != nil
        let hasOpenWork = openWorkToCheckCount > 0
        return !hasNext && !hasOpenWork
    }

    @ViewBuilder
    private var rightNowEmpty: some View {
        if hasNoRightNowContent {
            Text("All clear — nothing pressing.")
                .font(AppTheme.ScaledFont.callout)
                .italic()
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Next agenda item

    /// The first agenda item that hasn't been completed yet. Falls back to the first
    /// future item; if everything is done or empty, returns nil.
    var nextAgendaItem: AgendaItem? {
        viewModel.agendaItems.first { item in
            switch item {
            case .lesson(let sl):
                return !sl.isPresented
            case .meeting:
                return true
            case .scheduledWork, .followUp,
                 .groupedScheduledWork, .groupedFollowUp:
                return true
            }
        }
    }

    var openWorkToCheckCount: Int {
        viewModel.todaysSchedule.count + viewModel.staleFollowUps.count
    }

    @ViewBuilder
    private func nextUpRow(item: AgendaItem) -> some View {
        Button {
            startNextAgendaItem(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: nextUpIcon(for: item))
                    .font(.system(size: 14))
                    .foregroundStyle(nextUpColor(for: item))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next up")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(nextUpDescription(for: item))
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start next: \(nextUpDescription(for: item))")
    }

    @ViewBuilder
    private func openWorkRow(count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open work to check")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.primary)
                Text("^[\(count) item](inflect: true) waiting")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func nextUpDescription(for item: AgendaItem) -> String {
        switch item {
        case .lesson(let sl):
            let lessonName = nameForLesson(sl.resolvedLessonID)
            let students = studentNamesForIDs(sl.resolvedStudentIDs)
            if students.isEmpty { return lessonName }
            return "\(lessonName) — \(students)"
        case .meeting(let meeting):
            return "Meeting with \(meetingStudentName(for: meeting))"
        case .scheduledWork(let item):
            let lesson = resolveLessonName(for: item.work)
            let student = resolveStudentName(for: item.work)
            return "Check \(lesson) — \(student)"
        case .followUp(let item):
            let lesson = resolveLessonName(for: item.work)
            let student = resolveStudentName(for: item.work)
            return "Follow up: \(lesson) — \(student)"
        case .groupedScheduledWork(let items):
            let lesson = items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson"
            return "Check \(lesson) — \(items.count) students"
        case .groupedFollowUp(let items):
            let lesson = items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson"
            return "Follow up: \(lesson) — \(items.count) students"
        }
    }

    private func nextUpIcon(for item: AgendaItem) -> String {
        switch item {
        case .lesson: return "book.fill"
        case .meeting: return "person.crop.circle.badge.clock"
        case .scheduledWork, .groupedScheduledWork: return "clock.fill"
        case .followUp, .groupedFollowUp: return "arrow.uturn.left.circle.fill"
        }
    }

    private func nextUpColor(for item: AgendaItem) -> Color {
        switch item {
        case .lesson: return .blue
        case .meeting: return .teal
        case .scheduledWork, .groupedScheduledWork: return .orange
        case .followUp, .groupedFollowUp: return .purple
        }
    }

    private func startNextAgendaItem(_ item: AgendaItem) {
        switch item {
        case .lesson(let sl):
            selectedLessonAssignment = sl
        case .meeting(let meeting):
            startMeeting(meeting)
        case .scheduledWork(let item):
            selectedWorkID = item.work.id
        case .followUp(let item):
            selectedWorkID = item.work.id
        case .groupedScheduledWork(let items):
            if let id = items.first?.work.id { selectedWorkID = id }
        case .groupedFollowUp(let items):
            if let id = items.first?.work.id { selectedWorkID = id }
        }
    }
}
