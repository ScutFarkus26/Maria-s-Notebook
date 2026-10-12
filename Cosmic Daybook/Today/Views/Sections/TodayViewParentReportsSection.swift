// TodayViewParentReportsSection.swift
// Nudges the guide only while a monthly parent report cycle is actually open:
// the 1st through the end of day 7 of the month after the one being reported
// on, and only while some enrolled student's report is still unsent.
//
// It used to open on the 1st and never close, so a month where nothing was
// sent left the banner up for three weeks. A nudge she has declined twenty
// times is not what makes her send the reports; `TodaySectionVisibility`
// closes it at the end of the cycle window instead.

import SwiftUI
import CoreData

extension TodayView {

    var parentReportsListSection: some View {
        ParentReportsSectionView()
    }
}

struct ParentReportsSectionView: View {
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @TestStudentVisibility private var testStudents

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "enrollmentStatusRaw == %@", CDStudent.EnrollmentStatus.enrolled.rawValue)
    ) private var enrolledStudents: FetchedResults<CDStudent>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(
            format: "monthKey == %@ AND communicationTypeRaw == %@ AND sentAt != nil",
            ReportMonth.currentCycle().monthKey,
            CommunicationType.monthlyReport.rawValue
        )
    ) private var sentReports: FetchedResults<CDParentCommunication>

    private var cycle: ReportMonth { ReportMonth.currentCycle() }

    /// How many of the children counted (`studentIDs`) have a sent report,
    /// given the student id of every sent report row. Each child counts once
    /// (sync can leave two rows for one report), and only a child still
    /// counted: the banner said "23 of 22" with duplicates and children who
    /// had left (2026-10-11 #77).
    static func sentCount(sentReportStudentIDs: [String], studentIDs: Set<String>) -> Int {
        Set(sentReportStudentIDs).intersection(studentIDs).count
    }

    /// The last two days of the window, when the reports are about to be late.
    private func isRunningOut(now: Date, window: DateInterval) -> Bool {
        guard let twoDaysBeforeClose = calendar.date(byAdding: .day, value: -2, to: window.end) else {
            return false
        }
        return now >= twoDaysBeforeClose
    }

    var body: some View {
        let now = Date()
        let window = cycle.cycleWindow(calendar: calendar)
        // The class as the roster and the Parent Reports screen count it.
        let classIDs = Set(testStudents.visible(enrolledStudents).compactMap { $0.id?.uuidString })
        let total = classIDs.count
        let sent = Self.sentCount(sentReportStudentIDs: sentReports.map(\.studentID), studentIDs: classIDs)
        let isOverdue = isRunningOut(now: now, window: window)
        if TodaySectionVisibility.showsParentReports(now: now, window: window, enrolled: total, sent: sent) {
            Section {
                Button {
                    appRouter.navigateTo(.parentReports)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.badge.person.crop")
                            .foregroundStyle(isOverdue ? .red : .teal)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(sent) of \(total) \(cycle.displayName) reports sent")
                                .foregroundStyle(.primary)
                            Text(isOverdue
                                 ? "Due by the end of the week — finish and send"
                                 : "Draft, review, and send this month's family updates")
                                .font(.caption2)
                                .foregroundStyle(isOverdue ? .red : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            } header: {
                Text("Parent Reports")
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
        }
    }
}
