//
//  MigrationDiagnosticsView.swift
//  Maria's Notebook
//
//  Debug view for checking data integrity.
//

import SwiftUI
import SwiftData

#if DEBUG
struct MigrationDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isRunning = false
    @State private var report: MigrationDiagnosticReport?
    @State private var fixResult: MigrationFixResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status indicator
            if let report {
                statusBanner(report)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    runDiagnostics()
                } label: {
                    Label("Run Diagnostics", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                if let report, !report.isClean {
                    Button {
                        runFixes()
                    } label: {
                        Label("Fix Issues", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(isRunning)
                }
            }

            if isRunning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Running...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Fix result
            if let fixResult {
                fixResultBanner(fixResult)
            }

            // Quick stats
            if let report {
                quickStats(report)
            }
        }
    }

    private func statusBanner(_ report: MigrationDiagnosticReport) -> some View {
        HStack(spacing: 8) {
            Image(systemName: report.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isClean ? .green : .orange)

            Text(report.isClean ? "All data migrated correctly" : "Issues found")
                .font(.subheadline.weight(.medium))

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(report.isClean ? Color.green.opacity(UIConstants.OpacityConstants.light) : Color.orange.opacity(UIConstants.OpacityConstants.light))
        )
    }

    private func fixResultBanner(_ result: MigrationFixResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)

            Text(result.summary)
                .font(.caption)

            Spacer()

            Button {
                fixResult = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(UIConstants.OpacityConstants.light))
        )
    }

    private func quickStats(_ report: MigrationDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record Counts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statPill("LessonAssignments", count: report.counts.lessonAssignments, color: .green)
                statPill("Notes", count: report.counts.notes, color: .purple)
            }

            if !report.isClean {
                Divider()

                Text("Issues")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    if !report.lessonAssignmentIssues.isEmpty {
                        issuePill("LA Issues", count: report.lessonAssignmentIssues.count)
                    }
                    if !report.duplicateMigrations.isEmpty {
                        issuePill("Duplicates", count: report.duplicateMigrations.count, color: .red)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(UIConstants.OpacityConstants.light))
        )
    }

    private func statPill(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func issuePill(_ label: String, count: Int, color: Color = .orange) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(UIConstants.OpacityConstants.moderate)))
        .foregroundStyle(color)
    }

    private func runDiagnostics() {
        isRunning = true
        fixResult = nil

        Task {
            let service = MigrationDiagnosticService(context: modelContext)
            let result = await service.runDiagnostics()

            await MainActor.run {
                self.report = result
                self.isRunning = false
            }
        }
    }

    private func runFixes() {
        isRunning = true

        Task {
            let service = MigrationDiagnosticService(context: modelContext)
            let result = await service.fixCommonIssues()

            // Re-run diagnostics after fix
            let newReport = await service.runDiagnostics()

            await MainActor.run {
                self.fixResult = result
                self.report = newReport
                self.isRunning = false
            }
        }
    }
}

#Preview {
    MigrationDiagnosticsView()
}
#endif
