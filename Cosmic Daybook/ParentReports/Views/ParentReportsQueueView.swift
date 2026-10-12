// ParentReportsQueueView.swift
// Monthly review queue: one row per enrolled student for the selected cycle,
// with draft/review/send status. Drafts are AI-assisted but nothing sends
// without the guide's review.

import SwiftUI
import CoreData

struct ParentReportsQueueView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @State private var month = ReportMonth.currentCycle()
    @State private var reportsByStudent: [String: CDParentCommunication] = [:]
    @State private var guardianEmailsByStudent: [String: [String]] = [:]
    @State private var selectedStudent: CDStudent?
    @State private var isDraftingAll = false
    @State private var draftingProgress = ""

    @TestStudentVisibility private var testStudents

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "firstName", ascending: true),
            NSSortDescriptor(key: "lastName", ascending: true)
        ],
        predicate: NSPredicate(format: "enrollmentStatusRaw == %@", CDStudent.EnrollmentStatus.enrolled.rawValue),
        animation: .default
    ) private var enrolledStudents: FetchedResults<CDStudent>

    /// The class as the roster shows it: hidden test students and sync's
    /// duplicate rows left out, as the Today banner counts it.
    private var students: [CDStudent] {
        testStudents.visible(enrolledStudents)
    }

    private var sentCount: Int {
        students.filter { status(for: $0) == .sent }.count
    }

    var body: some View {
        List {
            Section {
                monthPicker
                progressRow
            }
            Section("Students") {
                ForEach(students, id: \.objectID) { student in
                    Button {
                        selectedStudent = student
                    } label: {
                        ParentReportQueueRow(
                            name: student.shortName,
                            level: student.level,
                            status: status(for: student),
                            sentAt: report(for: student)?.sentAt
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                draftAllButton
            } footer: {
                Text(
                    "Drafts are assembled only from what you recorded this month "
                    + "and are never sent without your review."
                )
            }
        }
        .quickCaptureButtonClearance()
        .navigationTitle("Parent Reports")
        .sheet(item: $selectedStudent) { student in
            ParentReportDraftEditorView(student: student, month: month) {
                reload()
            }
        }
        .onAppear(perform: reload)
        .onChange(of: month) { _, _ in reload() }
    }

    // MARK: - Rows

    private var monthPicker: some View {
        HStack {
            // The month stays put while Draft All Missing runs.
            Button {
                month = month.previous
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(isDraftingAll)
            Spacer()
            Text(month.displayName)
                .font(.headline)
            Spacer()
            Button {
                month = month.next
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(isDraftingAll || month == ReportMonth.currentCycle())
        }
        .padding(.vertical, 2)
    }

    private var progressRow: some View {
        HStack {
            Image(systemName: "envelope.badge.person.crop")
                .foregroundStyle(.teal)
            Text("\(sentCount) of \(students.count) \(month.displayName) reports sent")
            Spacer()
        }
        .font(.subheadline)
    }

    private var draftAllButton: some View {
        Button {
            draftAllMissing()
        } label: {
            if isDraftingAll {
                HStack {
                    ProgressView()
                    Text(draftingProgress)
                }
            } else {
                Label("Draft All Missing", systemImage: "wand.and.stars")
            }
        }
        .disabled(isDraftingAll || students.isEmpty)
    }

    // MARK: - Status

    private func report(for student: CDStudent) -> CDParentCommunication? {
        reportsByStudent[student.id?.uuidString ?? ""]
    }

    private func status(for student: CDStudent) -> ParentReportRowStatus {
        if let report = report(for: student) {
            switch report.status {
            case .sent: return .sent
            case .reviewed: return .reviewed
            case .draft: return .draft
            }
        }
        if (guardianEmailsByStudent[student.id?.uuidString ?? ""] ?? []).isEmpty {
            return .noGuardians
        }
        return .notStarted
    }

    private func reload() {
        reportsByStudent = dependencies.monthlyReportDraftService.reports(for: month)

        var emails: [String: [String]] = [:]
        let request = CDFetchRequest(CDGuardian.self)
        request.predicate = NSPredicate(format: "receivesReports == YES AND email != ''")
        for guardian in viewContext.safeFetch(request) {
            emails[guardian.studentID, default: []]
                .append(contentsOf: AttendanceEmail.parseRecipients(from: guardian.email))
        }
        guardianEmailsByStudent = emails
    }

    /// Drafts every report still missing for the month on screen when it
    /// starts. That month is captured and the arrows wait: the run used to
    /// read the screen's month after each draft, so switching months could
    /// redraft another month's reports, sent ones included (2026-10-11 #67).
    private func draftAllMissing() {
        let missing = students.filter { report(for: $0) == nil }
        guard !missing.isEmpty else { return }
        let draftingMonth = month
        isDraftingAll = true
        Task {
            await dependencies.monthlyReportDraftService.draftMissingReports(
                for: missing, month: draftingMonth
            ) { index, total in
                draftingProgress = "Drafting \(index) of \(total)…"
            }
            isDraftingAll = false
            draftingProgress = ""
            reload()
        }
    }
}

// MARK: - Row

enum ParentReportRowStatus {
    case noGuardians
    case notStarted
    case draft
    case reviewed
    case sent

    var label: String {
        switch self {
        case .noGuardians: return "No guardians"
        case .notStarted: return "Not started"
        case .draft: return "Draft"
        case .reviewed: return "Reviewed"
        case .sent: return "Sent"
        }
    }

    var color: Color {
        switch self {
        case .noGuardians: return AppColors.warning
        case .notStarted: return .secondary
        case .draft: return .blue
        case .reviewed: return .purple
        case .sent: return AppColors.success
        }
    }
}

private struct ParentReportQueueRow: View {
    let name: String
    let level: CDStudent.Level
    let status: ParentReportRowStatus
    let sentAt: Date?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(level.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let sentAt {
                Text(sentAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(status.label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(status.color.opacity(0.12), in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
