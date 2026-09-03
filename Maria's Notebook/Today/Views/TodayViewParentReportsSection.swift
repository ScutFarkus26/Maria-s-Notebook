// TodayViewParentReportsSection.swift
// Nudges the guide while a monthly parent report cycle is open: visible from
// the 1st of the month until every enrolled student's report for last month
// is sent, then disappears.

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

    private var cycleHasOpened: Bool {
        Date() >= cycle.cycleWindow(calendar: calendar).start
    }

    private var isOverdue: Bool {
        Date() > cycle.cycleWindow(calendar: calendar).end
    }

    var body: some View {
        let total = enrolledStudents.count
        let sent = sentReports.count
        if cycleHasOpened && total > 0 && sent < total {
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
                                 ? "Past the first week of the month — finish and send"
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
