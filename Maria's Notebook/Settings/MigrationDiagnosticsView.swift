//
//  MigrationDiagnosticsView.swift
//  Maria's Notebook
//
//  Debug view for checking migration status and fixing issues.
//

import SwiftUI
import SwiftData

#if DEBUG
struct MigrationDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isRunning = false
    @State private var report: MigrationDiagnosticReport?
    @State private var fixResult: MigrationFixResult?
    @State private var deleteResult: String?
    @State private var showingDetailedReport = false
    @State private var showingDeleteConfirmation = false
    @State private var orphanedRecords: [OrphanedRecordInfo] = []
    @State private var showingOrphanedDetails = false
    @State private var showingCorruptedSourceConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status indicator
            if let report = report {
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

                if report != nil && !report!.isClean {
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
            if let fixResult = fixResult {
                fixResultBanner(fixResult)
            }

            // Delete result
            if let deleteResult = deleteResult {
                deleteResultBanner(deleteResult)
            }

            // Quick stats
            if let report = report {
                quickStats(report)
            }

            // Detailed report button and delete button
            if let report = report, !report.isClean {
                HStack {
                    Button {
                        showingDetailedReport = true
                    } label: {
                        Label("View Detailed Report", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Spacer()

                    // Show delete button if there are unrecoverable issues
                    if hasUnrecoverableIssues(report) {
                        Button {
                            checkOrphansBeforeDelete()
                        } label: {
                            Label("Delete Orphans", systemImage: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }

                    // Show cleanup corrupted source button
                    if hasCorruptedSourceRecords(report) {
                        Button {
                            showingCorruptedSourceConfirmation = true
                        } label: {
                            Label("Clean Sources", systemImage: "trash.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showingDetailedReport) {
            if let report = report {
                DetailedReportView(report: report)
            }
        }
        .sheet(isPresented: $showingOrphanedDetails) {
            OrphanedRecordsDetailView(
                orphanedRecords: orphanedRecords,
                onDelete: {
                    showingOrphanedDetails = false
                    deleteUnrecoverableRecords()
                },
                onCancel: {
                    showingOrphanedDetails = false
                }
            )
        }
        .alert("Clean Up Corrupted Source Records?", isPresented: $showingCorruptedSourceConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCorruptedSourceRecords()
            }
        } message: {
            if let report = report {
                let slCount = report.corruptedStudentLessons.count
                let pCount = report.corruptedPresentations.count
                let noteCount = report.corruptedStudentLessons.reduce(0) { $0 + $1.noteCount } +
                               report.corruptedPresentations.reduce(0) { $0 + $1.noteCount }
                Text("This will permanently delete \(slCount) corrupted StudentLessons and \(pCount) corrupted Presentations that have empty studentIDs.\(noteCount > 0 ? " \(noteCount) notes will be orphaned." : "")")
            }
        }
    }

    private func hasCorruptedSourceRecords(_ report: MigrationDiagnosticReport) -> Bool {
        !report.corruptedStudentLessons.isEmpty || !report.corruptedPresentations.isEmpty
    }

    private func hasUnrecoverableIssues(_ report: MigrationDiagnosticReport) -> Bool {
        // Check if any lessonAssignmentIssues have empty studentIDs that can't be recovered
        report.lessonAssignmentIssues.contains { issue in
            issue.issues.contains("Empty studentIDs") &&
            (issue.sourceHadStudentIDs == false || issue.sourceHadStudentIDs == nil)
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
                .fill(report.isClean ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
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
                .fill(Color.blue.opacity(0.1))
        )
    }

    private func deleteResultBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)

            Spacer()

            Button {
                deleteResult = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }

    private func quickStats(_ report: MigrationDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record Counts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statPill("StudentLessons", count: report.counts.studentLessons, color: .blue)
                statPill("Presentations", count: report.counts.presentations, color: .purple)
                statPill("LessonAssignments", count: report.counts.lessonAssignments, color: .green)
            }

            if !report.isClean {
                Divider()

                Text("Issues")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    if !report.unmatchedStudentLessons.isEmpty {
                        issuePill("Unmigrated SL", count: report.unmatchedStudentLessons.count)
                    }
                    if !report.unmatchedPresentations.isEmpty {
                        issuePill("Unmigrated P", count: report.unmatchedPresentations.count)
                    }
                    if !report.notesOnlyOnLegacyPresentation.isEmpty {
                        issuePill("Notes (P)", count: report.notesOnlyOnLegacyPresentation.count)
                    }
                    if !report.notesOnlyOnLegacyStudentLesson.isEmpty {
                        issuePill("Notes (SL)", count: report.notesOnlyOnLegacyStudentLesson.count)
                    }
                    if !report.lessonAssignmentIssues.isEmpty {
                        issuePill("LA Issues", count: report.lessonAssignmentIssues.count)
                    }
                    if !report.corruptedStudentLessons.isEmpty {
                        issuePill("Corrupt SL", count: report.corruptedStudentLessons.count, color: .red)
                    }
                    if !report.corruptedPresentations.isEmpty {
                        issuePill("Corrupt P", count: report.corruptedPresentations.count, color: .red)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
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
        .background(Capsule().fill(color.opacity(0.2)))
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

    private func checkOrphansBeforeDelete() {
        let service = MigrationDiagnosticService(context: modelContext)
        orphanedRecords = service.checkOrphanedRecordsForNotes()
        showingOrphanedDetails = true
    }

    private func deleteUnrecoverableRecords() {
        isRunning = true
        deleteResult = nil

        Task {
            let service = MigrationDiagnosticService(context: modelContext)
            let deletedCount = service.deleteUnrecoverableRecords()

            // Re-run diagnostics after deletion
            let newReport = await service.runDiagnostics()

            await MainActor.run {
                self.deleteResult = "Deleted \(deletedCount) orphaned record\(deletedCount == 1 ? "" : "s")"
                self.report = newReport
                self.isRunning = false
            }
        }
    }

    private func deleteCorruptedSourceRecords() {
        isRunning = true
        deleteResult = nil

        Task {
            let service = MigrationDiagnosticService(context: modelContext)
            let result = service.deleteCorruptedSourceRecords()

            // Re-run diagnostics after deletion
            let newReport = await service.runDiagnostics()

            await MainActor.run {
                self.deleteResult = result.summary
                self.report = newReport
                self.isRunning = false
            }
        }
    }
}

// MARK: - Orphaned Records Detail View

private struct OrphanedRecordsDetailView: View {
    let orphanedRecords: [OrphanedRecordInfo]
    let onDelete: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var totalNotes: Int {
        orphanedRecords.reduce(0) { $0 + $1.noteCount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The following \(orphanedRecords.count) record\(orphanedRecords.count == 1 ? "" : "s") cannot be recovered because the source data is missing or corrupted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if totalNotes > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("\(totalNotes) note\(totalNotes == 1 ? "" : "s") will be orphaned if you delete these records.")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Orphaned Records") {
                    ForEach(orphanedRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.lessonTitle)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(record.state)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }

                            Text("ID: \(record.id.uuidString.prefix(8))...")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            if record.hasNotes {
                                HStack {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                    Text("\(record.noteCount) note\(record.noteCount == 1 ? "" : "s")")
                                        .font(.caption)
                                }
                                .foregroundStyle(.orange)

                                ForEach(record.notePreviews, id: \.self) { preview in
                                    Text("• \"\(preview)...\"")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Orphaned Records")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete All", role: .destructive) { onDelete() }
                }
            }
        }
    }
}

// MARK: - Detailed Report View

private struct DetailedReportView: View {
    let report: MigrationDiagnosticReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report.detailedReport())
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Migration Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report.detailedReport())
                }
            }
        }
    }
}

#Preview {
    MigrationDiagnosticsView()
}
#endif
