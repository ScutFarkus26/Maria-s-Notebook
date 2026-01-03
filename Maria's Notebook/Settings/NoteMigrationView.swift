import SwiftUI
import SwiftData

/// View for migrating legacy notes to the unified Note system
struct NoteMigrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var migrationState: MigrationState = .idle
    @State private var summary: MigrationSummary?
    @State private var verificationResults: VerificationResults?
    @State private var errorMessage: String?
    @State private var showingConfirmation = false
    
    enum MigrationState {
        case idle
        case counting
        case migrating
        case completed
        case failed
    }
    
    @State private var counts: LegacyNoteCounts?
    
    struct LegacyNoteCounts {
        let scopedNotes: Int
        let workNotes: Int
        let meetingNotes: Int
        
        var total: Int {
            scopedNotes + workNotes + meetingNotes
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            
            if let counts = counts {
                countsSection(counts)
            }
            
            if let summary = summary {
                resultsSection(summary)
            }
            
            if let verificationResults = verificationResults {
                verificationSection(verificationResults)
            }
            
            if let errorMessage = errorMessage {
                errorSection(errorMessage)
            }
            
            Spacer()
            
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            countLegacyNotes()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note Migration")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Migrate legacy notes (ScopedNote, WorkNote, MeetingNote) to the unified Note system. This will create new Note objects while preserving all existing data.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func countsSection(_ counts: LegacyNoteCounts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legacy Notes Found")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            
            VStack(alignment: .leading, spacing: 8) {
                countRow("ScopedNote", count: counts.scopedNotes)
                countRow("WorkNote", count: counts.workNotes)
                countRow("MeetingNote", count: counts.meetingNotes)
                
                Divider()
                
                HStack {
                    Text("Total")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(counts.total)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
    
    private func countRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, design: .rounded))
            Spacer()
            Text("\(count)")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func resultsSection(_ summary: MigrationSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Migration Results")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            
            VStack(alignment: .leading, spacing: 8) {
                resultRow("ScopedNote", count: summary.scopedNotesMigrated)
                resultRow("WorkNote", count: summary.workNotesMigrated)
                resultRow("MeetingNote", count: summary.meetingNotesMigrated)
                
                Divider()
                
                HStack {
                    Text("Total Migrated")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(summary.total)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.1))
            )
        }
    }
    
    private func resultRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, design: .rounded))
            Spacer()
            Text("\(count)")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.green)
        }
    }
    
    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }
            
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
    }
    
    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if migrationState == .idle, let counts = counts, counts.total > 0 {
                Button("Migrate All") {
                    showingConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if migrationState == .migrating {
                ProgressView()
                    .padding(.horizontal, 16)
            } else if migrationState == .completed {
                HStack {
                    Button("Verify") {
                        verifyMigration()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Confirm Migration", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Migrate", role: .destructive) {
                performMigration()
            }
        } message: {
            if let counts = counts {
                Text("This will migrate \(counts.total) legacy notes to the unified Note system. This action cannot be undone, but your original notes will remain in the database.")
            }
        }
    }
    
    private func countLegacyNotes() {
        migrationState = .counting
        Task { @MainActor in
            do {
                let scopedCount = try modelContext.fetch(FetchDescriptor<ScopedNote>()).count
                let workCount = try modelContext.fetch(FetchDescriptor<WorkNote>()).count
                let meetingCount = try modelContext.fetch(FetchDescriptor<MeetingNote>()).count
                
                self.counts = LegacyNoteCounts(
                    scopedNotes: scopedCount,
                    workNotes: workCount,
                    meetingNotes: meetingCount
                )
                self.migrationState = .idle
            } catch {
                self.errorMessage = "Failed to count legacy notes: \(error.localizedDescription)"
                self.migrationState = .failed
            }
        }
    }
    
    private func performMigration() {
        migrationState = .migrating
        errorMessage = nil
        summary = nil
        
        Task { @MainActor in
            do {
                let helper = NoteMigrationHelper(modelContext: modelContext)
                let result = try helper.migrateAll()
                
                self.summary = result
                self.migrationState = .completed
                
                // Recount to show updated numbers
                countLegacyNotes()
            } catch {
                self.errorMessage = "Migration failed: \(error.localizedDescription)"
                self.migrationState = .failed
            }
        }
    }
    
    private func verifyMigration() {
        Task { @MainActor in
            do {
                let helper = NoteMigrationHelper(modelContext: modelContext)
                let results = try helper.verifyMigration()
                self.verificationResults = results
            } catch {
                self.errorMessage = "Verification failed: \(error.localizedDescription)"
            }
        }
    }
    
    @ViewBuilder
    private func verificationSection(_ results: VerificationResults) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Verification Results")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                
                Spacer()
                
                if results.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if results.scopedNotesVerified > 0 {
                    verificationRow("ScopedNote", verified: results.scopedNotesVerified, errors: results.scopedNotesErrors, notMigrated: results.scopedNotesNotMigrated)
                }
                if results.workNotesVerified > 0 {
                    verificationRow("WorkNote", verified: results.workNotesVerified, errors: results.workNotesErrors, notMigrated: results.workNotesNotMigrated)
                }
                if results.meetingNotesVerified > 0 {
                    verificationRow("MeetingNote", verified: results.meetingNotesVerified, errors: results.meetingNotesErrors, notMigrated: results.meetingNotesNotMigrated)
                }
                
                Divider()
                
                HStack {
                    Text("Total Verified")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(results.totalVerified)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(results.isComplete ? .green : .orange)
                }
                
                if results.totalErrors > 0 {
                    HStack {
                        Text("Errors")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(results.totalErrors)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                
                if results.totalNotMigrated > 0 {
                    HStack {
                        Text("Not Migrated")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("\(results.totalNotMigrated)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(results.isComplete ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            )
        }
    }
    
    private func verificationRow(_ label: String, verified: Int, errors: Int, notMigrated: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            HStack {
                if verified > 0 {
                    Label("\(verified) verified", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if errors > 0 {
                    Label("\(errors) errors", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if notMigrated > 0 {
                    Label("\(notMigrated) not migrated", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Sheet Wrapper
struct NoteMigrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NoteMigrationView()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
    }
}

