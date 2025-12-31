import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private let backupService = BackupService()
    @StateObject private var viewModel = SettingsViewModel()

    // Live data for stats
    @Query private var students: [Student]
    @Query private var items: [Item]
    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt == nil })
    private var plannedLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt != nil })
    private var givenLessons: [StudentLesson]

    // Export / Import state
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importError: String? = nil
    @State private var showRestoreConfirm = false
    @State private var showingDuplicatesPreview = false
    @State private var maintenanceAlert: (title: String, message: String)? = nil
    @State private var pendingImporterPresentation = false
    @AppStorage("LastBackupTimeInterval") private var lastBackupTimeInterval: Double = 0

    @AppStorage("Backup.encrypt") private var encryptBackups: Bool = false
    @State private var restoreMode: BackupService.RestoreMode = .merge

    // New state properties for Advanced / Debug section
    @State private var showDannyResetConfirm = false
    @State private var showPurgeLegacyWorkConfirm = false
    @State private var dannyResetSummary: String? = nil
    @State private var seedSummary: String? = nil

    @State private var showingFolderImporter = false

    private let overviewColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    private var exportDocument: BackupPackageDocument? { viewModel.exportData.map { BackupPackageDocument(data: $0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Overview Section
                    SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
                        OverviewStatsGrid(
                            studentsCount: studentsTotal,
                            lessonsCount: lessonsTotal,
                            plannedCount: plannedTotal,
                            givenCount: givenTotal,
                            columns: overviewColumns
                        )
                    }
                    
                    // MARK: - Data Management Section
                    dataManagementSection
                    
                    // MARK: - School Configuration Section
                    schoolConfigurationSection
                    
                    // MARK: - Attendance Section
                    attendanceSection
                    
                    // MARK: - Advanced / Debug Section
                    advancedDebugSection
                }
                .frame(maxWidth: 900)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
            defaultFilename: viewModel.defaultBackupFilename()
        ) { result in
            switch result {
            case .success:
                viewModel.setLastBackupNow()
                viewModel.resultSummary = "Exported backup successfully."
            case .failure(let error):
                viewModel.importError = "Failed to write backup: \(error.localizedDescription)"
            }
            viewModel.exportData = nil
            viewModel.backupProgress = 0; viewModel.backupMessage = ""
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: BackupFile.fileExtension) ?? .data]
        ) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.previewImportedURL(modelContext: modelContext, url: url) }
            case .failure(let error):
                viewModel.importError = "Failed to restore: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder]
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let url):
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try BackupDestination.setDefaultFolder(url)
                        viewModel.loadDefaultFolderName()
                    } catch {
                        print("Error setting default folder: \(error)")
                    }
                case .failure:
                    break
                }
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { maintenanceAlert != nil },
            set: { if !$0 { maintenanceAlert = nil } }
        )) {
            Alert(
                title: Text(maintenanceAlert?.title ?? "Maintenance"),
                message: Text(maintenanceAlert?.message ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingDuplicatesPreview) {
            DuplicateStudentsPreviewView { summary in
                let message = "Groups of Students considered: \(summary.groupsConsidered)\nGroups of Students merged: \(summary.groupsMerged)\nStudents deleted: \(summary.studentsDeleted)\nReferences updated: \(summary.referencesUpdated)"
                maintenanceAlert = (title: "Merge Complete", message: message)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CreateBackupRequested"))) { _ in
            Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RestoreBackupRequested"))) { _ in
            showRestoreConfirm = true
        }
        .onChange(of: showRestoreConfirm) { _, newValue in
            if newValue == false && pendingImporterPresentation {
                showingImporter = true
                pendingImporterPresentation = false
            }
        }
        // New alert for confirmation of delete Danny & Lil Dan D history
        .alert("Delete History?", isPresented: $showDannyResetConfirm) {
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    do {
                        let summary = try StudentDataWiper.wipeDannyAndLilDanD(using: modelContext)
                        dannyResetSummary = summary
                        _ = SaveCoordinator().save(modelContext, reason: "Admin wipe Danny + Lil Dan D history")
                    } catch {
                        dannyResetSummary = "Failed to delete history: \(error.localizedDescription)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action will permanently delete all lesson and work history for the students named “Danny de Berry” and “Lil Dan D”. This cannot be undone.")
        }
        .alert("Purge Legacy WorkModel Data?", isPresented: $showPurgeLegacyWorkConfirm) {
            Button("Purge", role: .destructive) {
                Task { @MainActor in
                    do {
                        // Delete all legacy WorkModel-related entities
                        try modelContext.delete(model: WorkCheckIn.self)
                        try modelContext.delete(model: WorkNote.self)
                        try modelContext.delete(model: WorkParticipantEntity.self)
                        try modelContext.delete(model: WorkModel.self)
                        try modelContext.save()
                        maintenanceAlert = (title: "Purge Complete", message: "All WorkModel, WorkParticipantEntity, WorkNote, and WorkCheckIn records have been deleted.")
                    } catch {
                        maintenanceAlert = (title: "Purge Failed", message: error.localizedDescription)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all legacy WorkModel data and related entities. This cannot be undone.")
        }
        // New alert showing completion summary
        .alert("History Deleted", isPresented: Binding(get: { dannyResetSummary != nil }, set: { if !$0 { dannyResetSummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dannyResetSummary ?? "")
        }
        // Alert for seed/scan summary
        .alert("Operation Complete", isPresented: Binding(get: { seedSummary != nil }, set: { if !$0 { seedSummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedSummary ?? "")
        }
        // Sheet presenting the operation summary from import/export
        .sheet(item: $viewModel.operationSummary) { summary in
            BackupSummaryView(summary: summary)
        }
        .sheet(isPresented: Binding(get: { viewModel.restorePreviewData != nil }, set: { if !$0 { viewModel.restorePreviewData = nil } })) {
            if let preview = viewModel.restorePreviewData {
                RestorePreviewView(
                    preview: preview,
                    onCancel: {
                        viewModel.restorePreviewData = nil
                    },
                    onConfirm: {
                        Task { await viewModel.performImportConfirmed(modelContext: modelContext) }
                    }
                )
            }
        }
        .onAppear {
            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            // We infer this by the absence of the in-memory flag being set by App startup code.
            if !UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            }
            viewModel.loadDefaultFolderName()
        }
#if os(iOS)
        .onChange(of: viewModel.exportData) { newValue in
            showingExporter = (newValue != nil)
        }
#endif
    }

    // Extracted sections to reduce type-checker complexity
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data Management")
            HStack(alignment: .top, spacing: 24) {
                backupRestorePane
                    .frame(maxWidth: .infinity)
                maintenancePane
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var backupRestorePane: some View {
        BackupRestoreSettingsView(
            encryptBackups: $encryptBackups,
            restoreMode: $viewModel.restoreMode,
            backupProgress: $viewModel.backupProgress,
            backupMessage: $viewModel.backupMessage,
            importProgress: $viewModel.importProgress,
            importMessage: $viewModel.importMessage,
            resultSummary: $viewModel.resultSummary,
            defaultFolderName: $viewModel.defaultFolderName,
            lastBackupDate: viewModel.lastBackupDate,
            performExport: { Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) } },
            presentImporter: { showingImporter = true },
            chooseDefaultFolder: {
#if os(macOS)
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    try? BackupDestination.setDefaultFolder(url)
                    viewModel.loadDefaultFolderName()
                }
#else
                showingFolderImporter = true
#endif
            },
            openDefaultFolder: {
#if os(macOS)
                if let url = BackupDestination.resolveDefaultFolder() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
#else
                if let url = BackupDestination.resolveDefaultFolder() {
                    UIApplication.shared.open(url)
                }
#endif
            },
            clearDefaultFolder: {
                BackupDestination.clearDefaultFolder()
                viewModel.loadDefaultFolderName()
            }
        )
    }

    private var maintenancePane: some View {
        MaintenanceSettingsView(
            maintenanceAlert: $maintenanceAlert,
            onMergeDuplicates: {
                do {
                    let summary = try StudentDuplicatesCleaner.mergeDuplicates(using: modelContext)
                    let message = "Groups of Students considered: \(summary.groupsConsidered)\nGroups of Students merged: \(summary.groupsMerged)\nStudents deleted: \(summary.studentsDeleted)\nReferences updated: \(summary.referencesUpdated)"
                    maintenanceAlert = (title: "Merge Duplicate Students", message: message)
                } catch {
                    maintenanceAlert = (title: "Merge Failed", message: error.localizedDescription)
                }
            },
            onPreviewDuplicates: {
                showingDuplicatesPreview = true
            },
            onCleanupZeroStudentLessons: {
                do {
                    let summary = try StudentLessonCleaner.removeZeroStudentLessons(using: modelContext)
                    let msg = "Zero-student lessons found: \(summary.totalFound)\nDeleted: \(summary.deleted)\nWork links cleared: \(summary.worksCleared)"
                    maintenanceAlert = (title: "Remove Zero-Student Lessons", message: msg)
                } catch {
                    maintenanceAlert = (title: "Cleanup Failed", message: error.localizedDescription)
                }
            }
        )
    }

    private var schoolConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "School Configuration")
            SettingsGroup(title: "School Calendar", systemImage: "calendar.badge.exclamationmark") {
                SchoolCalendarSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Attendance")
            HStack(alignment: .top, spacing: 24) {
                SettingsGroup(title: "Present Now Filters", systemImage: "line.3.horizontal.decrease.circle") {
                    PresentNowSettingsView()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                
                SettingsGroup(title: "Email Reports", systemImage: "envelope") {
                    AttendanceEmailSettingsView()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var advancedDebugSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Advanced / Debug")
            DebugToolsView(
                showDannyResetConfirm: $showDannyResetConfirm,
                showPurgeLegacyWorkConfirm: $showPurgeLegacyWorkConfirm,
                onScanAndQueue: {
                    Task { @MainActor in
                        do {
                            let result = try scanAndBackfillBlockedLessonsGrouped(modelContext: modelContext)
                            seedSummary = result
                        } catch {
                            seedSummary = "Error: \(error.localizedDescription)"
                        }
                    }
                },
                onConsolidate: {
                    Task { @MainActor in
                        do {
                            let result = try consolidateOnDeckLessons(modelContext: modelContext)
                            seedSummary = result
                        } catch {
                            seedSummary = "Error: \(error.localizedDescription)"
                        }
                    }
                }
            )
        }
    }

    private var studentsTotal: Int { students.count }
    private var lessonsTotal: Int { lessons.count }
    private var plannedTotal: Int { plannedLessons.count }
    private var givenTotal: Int { givenLessons.count }
}

#Preview {
    SettingsView()
}

