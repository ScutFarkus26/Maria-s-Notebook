import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Live data for stats
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt == nil })
    private var plannedLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt != nil })
    private var givenLessons: [StudentLesson]

    // New state properties for Advanced / Debug section
    @State private var showDannyResetConfirm = false
    @State private var showPurgeLegacyWorkConfirm = false
    @State private var dannyResetSummary: String? = nil
    @State private var seedSummary: String? = nil

    @State private var maintenanceAlert: (title: String, message: String)? = nil
    @State private var showingDuplicatesPreview = false

    private let overviewColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
                    
                    // MARK: - Attendance Section
                    attendanceSection
                    
                    // MARK: - School Configuration Section
                    schoolConfigurationSection
                    
                    // MARK: - Data Management Section
                    dataManagementSection
                    
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
        .onAppear {
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "SettingsView",
                itemCounts: [
                    "students": students.count,
                    "lessons": lessons.count,
                    "studentLessons": studentLessons.count,
                    "plannedLessons": plannedLessons.count,
                    "givenLessons": givenLessons.count
                ]
            )
            #endif
        }
        .alert(isPresented: isMaintenanceAlertPresented) {
            Alert(
                title: Text(maintenanceAlert?.title ?? "Maintenance"),
                message: Text(maintenanceAlert?.message ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
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
        .alert("History Deleted", isPresented: isDannyResetSummaryPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dannyResetSummary ?? "")
        }
        // Alert for seed/scan summary
        .alert("Operation Complete", isPresented: isSeedSummaryPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedSummary ?? "")
        }
        .sheet(isPresented: $showingDuplicatesPreview) {
            DuplicateStudentsPreviewView { summary in
                let message = "Groups of Students considered: \(summary.groupsConsidered)\nGroups of Students merged: \(summary.groupsMerged)\nStudents deleted: \(summary.studentsDeleted)\nReferences updated: \(summary.referencesUpdated)"
                maintenanceAlert = (title: "Merge Complete", message: message)
            }
        }
        .onAppear {
            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            if !UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            }
        }
    }

    // Extracted sections to reduce type-checker complexity
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data Management")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible(), spacing: 24)
            ], spacing: 24) {
                backupRestorePane
                    .frame(maxWidth: .infinity)
                maintenancePane
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var backupRestorePane: some View {
        BackupRestoreSectionView()
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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible(), spacing: 24)
            ], spacing: 24) {
                SettingsGroup(title: "Present Now", systemImage: "line.3.horizontal.decrease.circle") {
                    PresentNowSettingsView()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                SettingsGroup(title: "Attendance Email", systemImage: "envelope") {
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

    // Extracted Bindings to reduce type-checker complexity
    private var isMaintenanceAlertPresented: Binding<Bool> {
        Binding<Bool>(
            get: { maintenanceAlert != nil },
            set: { if !$0 { maintenanceAlert = nil } }
        )
    }

    private var isDannyResetSummaryPresented: Binding<Bool> {
        Binding<Bool>(
            get: { dannyResetSummary != nil },
            set: { if !$0 { dannyResetSummary = nil } }
        )
    }

    private var isSeedSummaryPresented: Binding<Bool> {
        Binding<Bool>(
            get: { seedSummary != nil },
            set: { if !$0 { seedSummary = nil } }
        )
    }

    private var studentsTotal: Int { students.count }
    private var lessonsTotal: Int { lessons.count }
    private var plannedTotal: Int { plannedLessons.count }
    private var givenTotal: Int { givenLessons.count }
}

#Preview {
    SettingsView()
}

