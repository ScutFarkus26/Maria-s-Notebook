// RecallQueueView.swift
// The lesson-recall queue, inside the Students area. Shows a retention summary for the year
// (the "track it" payoff) plus, per student, the strands due for a post-break recall check —
// each collapsed to the frontier (most advanced mastered lesson) with a "covers N" badge.
// Tapping a row opens the check sheet; recording an outcome reloads so completed items fall away.

import SwiftUI

struct RecallQueueView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel = RecallQueueViewModel()
    @State private var selectedEntry: RecallQueueEntry?

    private var showEmpty: Bool {
        !viewModel.hasContent && (viewModel.summary?.hasAnything != true)
    }

    var body: some View {
        Group {
            if showEmpty {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text("No recall checks recorded yet, and nothing is due right now.")
                }
            } else {
                List {
                    if let summary = viewModel.summary, summary.hasAnything {
                        retentionSection(summary)
                        if !viewModel.retentionByStudent.isEmpty {
                            Section("By student") {
                                ForEach(viewModel.retentionByStudent) { row in
                                    HStack {
                                        Text(row.name)
                                        Spacer()
                                        Text(row.percent.map { "\($0)%" } ?? "—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if viewModel.hasContent {
                        ForEach(viewModel.sections) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    Button { selectedEntry = entry } label: {
                                        RecallQueueRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack {
                                    Text(section.studentName)
                                    Spacer()
                                    Text("\(section.entries.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Section {
                            Text("No lessons are due for a recall check right now.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Lesson Recall")
        .onAppear { reload() }
        .sheet(item: $selectedEntry) { entry in
            RecallCheckSheet(entry: entry) { reload() }
        }
    }

    @ViewBuilder
    private func retentionSection(_ summary: RecallRetentionStats.Summary) -> some View {
        Section("Retention this year") {
            HStack {
                metric("Held", summary.retentionPercent.map { "\($0)%" } ?? "—")
                Spacer()
                metric("Checked", "\(summary.observedCount)")
                Spacer()
                metric("Re-present", "\(summary.representCount)")
            }
            if let fade = viewModel.fadeOverSummerPercent {
                Text("Faded over summer: \(fade)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func reload() {
        viewModel.loadData(context: viewContext, schoolYearStore: dependencies.schoolYearStore)
    }
}

private struct RecallQueueRow: View {
    let entry: RecallQueueEntry

    private var dueLabel: String {
        switch entry.dueReason {
        case .startOfYearSweep: return "summer recall"
        case .spacedDue: return "due for re-check"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.frontierLessonName)
                Text("\(entry.area) · \(entry.sequence) · \(dueLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.coversCount > 0 {
                Text("covers \(entry.coversCount)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
