// LessonsAndWorkReportsView.swift
// The Reports half of Lessons & Work (2026-10-30): every child's report by
// stage, who presents to the class soon, and what was presented this school
// year. A row opens the report; its stage is a menu.
// Plan: docs/Plans/Plan - Reports and to-dos in meetings.md

import SwiftUI
import CoreData

struct LessonsAndWorkReportsView: View {
    let searchText: String
    let studentsByID: [UUID: CDStudent]
    let onOpenWork: (CDWorkModel) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: true)],
        predicate: NSPredicate(format: "kindRaw == %@", WorkKind.report.rawValue)
    )
    private var reportRows: FetchedResults<CDWorkModel>

    @State private var showsPresented = false

    var body: some View {
        let board = ReportBoard.make(
            from: Array(reportRows), yearStart: dependencies.schoolYearStore.current.start, context: viewContext
        )
        Group {
            if board.isEmpty {
                ContentUnavailableView(
                    "No Reports Yet",
                    systemImage: "doc.text",
                    description: Text("Start a report from a child's meeting, and it shows here by stage.")
                )
            } else {
                List {
                    if !matching(board.presentingSoon).isEmpty {
                        Section("Presenting Soon") {
                            ForEach(matching(board.presentingSoon)) { report in
                                row(report)
                            }
                        }
                    }
                    ForEach(board.stages) { group in
                        let reports = matching(group.reports)
                        if !reports.isEmpty {
                            Section("\(group.name) · \(reports.count)") {
                                ForEach(reports) { row($0) }
                            }
                        }
                    }
                    if !matching(board.resting).isEmpty {
                        Section("Resting") {
                            ForEach(matching(board.resting)) { row($0) }
                        }
                    }
                    if !matching(board.presented).isEmpty {
                        Section {
                            DisclosureGroup(
                                "Presented This Year · \(matching(board.presented).count)",
                                isExpanded: $showsPresented
                            ) {
                                ForEach(matching(board.presented)) { row($0) }
                            }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                #endif
            }
        }
    }

    // MARK: - Rows

    private func row(_ report: ReportBoard.Report) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                onOpenWork(report.anchor)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: report))
                        .foregroundStyle(Color.primary)
                    Text(detail(of: report))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            stageMenu(report)
        }
        .padding(.vertical, 2)
    }

    private func stageMenu(_ report: ReportBoard.Report) -> some View {
        let titles = ReportStages.titles(of: report.anchor)
        let current = ReportStages.currentStage(of: report.anchor)
        return Menu {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, name in
                Button {
                    setStage(index, of: report)
                } label: {
                    if index == current || (current == nil && index == titles.count - 1) {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Text(report.stageName)
                .font(.subheadline)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("Stage: \(report.stageName)")
    }

    private func setStage(_ stage: Int, of report: ReportBoard.Report) {
        guard ReportStages.setStage(stage, of: report.anchor, context: viewContext, saveCoordinator: saveCoordinator)
        else {
            ToastService.shared.showError("Couldn't move the report. Try again.")
            return
        }
    }

    // MARK: - Words

    private func title(of report: ReportBoard.Report) -> String {
        let title = report.anchor.title.trimmed()
        return title.isEmpty ? "Report" : title
    }

    private func names(of report: ReportBoard.Report) -> String {
        ListFormatter.localizedString(byJoining: report.studentIDs.compactMap { studentsByID[$0]?.shortName })
    }

    private func detail(of report: ReportBoard.Report) -> String {
        var parts = [names(of: report)].filter { !$0.isEmpty }
        if let presentedOn = report.presentedOn {
            parts.append("presented \(DateFormatters.shortMonthDay.string(from: presentedOn))")
            return parts.joined(separator: " · ")
        }
        if let created = report.anchor.createdAt {
            let days = AppCalendar.shared.dateComponents([.day], from: created, to: Date()).day ?? 0
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        if report.isResting, let until = report.anchor.restingUntil {
            parts.append("resting till \(DateFormatters.shortMonthDay.string(from: until))")
        } else if let day = report.presentDay {
            parts.append("presents \(DateFormatters.shortMonthDay.string(from: day))")
        }
        return parts.joined(separator: " · ")
    }

    /// The reports whose title or children match the search field.
    private func matching(_ reports: [ReportBoard.Report]) -> [ReportBoard.Report] {
        let query = searchText.trimmed()
        guard !query.isEmpty else { return reports }
        return reports.filter { report in
            report.anchor.title.localizedStandardContains(query)
                || report.studentIDs.contains { studentsByID[$0]?.fullName.localizedStandardContains(query) ?? false }
        }
    }
}
