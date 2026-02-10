import SwiftUI
import SwiftData

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // OPTIMIZATION: Use ViewModel for efficient statistics loading instead of loading entire tables
    @StateObject private var statsViewModel = SettingsStatsViewModel()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var overviewColumns: [GridItem] {
        // Use 2 columns on iPhone (compact), 4 columns on iPad (regular)
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        // NavigationStack is needed for NavigationLink destinations (e.g., NoteTemplateManagementView)
        // to work correctly when SettingsView is displayed in a NavigationSplitView detail pane.
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Settings")
                Divider()
                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - 1. General
                        generalSection

                        // MARK: - 2. Data & Sync
                        dataSyncSection

                        // MARK: - 3. Backup & Data Management
                        backupManagementSection

                        // MARK: - 4. Templates
                        templatesSection

                        // MARK: - 5. Communication
                        communicationSection

                        // MARK: - 6. AI Features
                        aiFeaturesSection

                        // MARK: - 7. Database
                        databaseSection

                        #if DEBUG
                        // MARK: - 8. Advanced (Debug Only)
                        advancedSection
                        #endif
                    }
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            // OPTIMIZATION: Load statistics efficiently via ViewModel
            statsViewModel.loadCounts(context: modelContext)

            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            }
        }
    }

    // MARK: - Section Definitions
    
    // 1. General
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "General", systemImage: "gear")
            VStack(spacing: 12) {
                SettingsGroup(title: "School Calendar", systemImage: "calendar.badge.exclamationmark") {
                    SchoolCalendarSettingsView()
                        .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Display & Colors", systemImage: "paintpalette.fill") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lesson Age Indicators")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LessonAgeSettingsView()
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Work Age Indicators")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            WorkAgeSettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // 2. Data & Sync
    private var dataSyncSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data & Sync", systemImage: "arrow.triangle.2.circlepath")
            VStack(spacing: 12) {
                SettingsGroup(title: "iCloud", systemImage: "icloud.fill") {
                    VStack(spacing: 12) {
                        CloudKitStatusSettingsView()
                        
                        Divider()
                        
                        iCloudBackupToggle
                    }
                    .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Reminders", systemImage: "bell.fill") {
                    ReminderSyncSettingsView()
                        .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Calendar", systemImage: "calendar") {
                    CalendarSyncSettingsView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // 3. Backup & Data Management
    private var backupManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Backup & Data Management", systemImage: "externaldrive.fill")
            DataManagementGrid()
        }
    }
    
    // 4. Templates
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Templates", systemImage: "doc.on.doc.fill")
            VStack(spacing: 12) {
                SettingsGroup(title: "Note Templates", systemImage: "note.text.badge.plus") {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(statsViewModel.noteTemplatesCount)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Templates Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
                        NavigationLink {
                            NoteTemplateManagementView()
                        } label: {
                            HStack {
                                Text("Manage Templates")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                SettingsGroup(title: "Meeting Templates", systemImage: "person.2.fill") {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(statsViewModel.meetingTemplatesCount)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Templates Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
                        NavigationLink {
                            MeetingTemplateManagementView()
                        } label: {
                            HStack {
                                Text("Manage Templates")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // 5. Communication
    private var communicationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Communication", systemImage: "envelope.fill")
            SettingsGroup(title: "Attendance Email", systemImage: "checkmark.circle.fill") {
                AttendanceEmailSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // 6. AI Features
    private var aiFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "AI Features", systemImage: "brain.head.profile")
            SettingsGroup(title: "Development Insights", systemImage: "sparkles") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude AI Integration")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            if AnthropicAPIClient.hasAPIKey() {
                                Label("API key configured", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("API key required", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    NavigationLink {
                        APIKeySettingsView()
                    } label: {
                        HStack {
                            Text("Configure API Key")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // 7. Database
    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Database", systemImage: "cylinder.fill")
            SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
                // Row 1: Core (Existing)
                OverviewStatsGrid(
                    studentsCount: statsViewModel.studentsCount,
                    lessonsCount: statsViewModel.lessonsCount,
                    plannedCount: statsViewModel.plannedCount,
                    givenCount: statsViewModel.givenCount,
                    columns: overviewColumns
                )
                
                Divider()
                
                // Row 2: Detail (New)
                LazyVGrid(columns: overviewColumns, spacing: 16) {
                    StatCard(title: "Work Items", value: "\(statsViewModel.workModelsCount)", subtitle: "Assigned", systemImage: "doc.text.fill")
                    StatCard(title: "Presentations", value: "\(statsViewModel.presentationsCount)", subtitle: "History", systemImage: "paintpalette.fill")
                    StatCard(title: "Observations", value: "\(statsViewModel.notesCount)", subtitle: "Notes", systemImage: "note.text")
                    StatCard(title: "Meetings", value: "\(statsViewModel.meetingsCount)", subtitle: "Records", systemImage: "person.2.fill")
                }
            }
        }
    }
    
    #if DEBUG
    // 7. Advanced (Debug Only)
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Advanced", systemImage: "wrench.and.screwdriver.fill")
            SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    #endif
    
    // iCloud Backup Toggle (extracted from DataManagementGrid)
    @AppStorage("CloudBackup.scheduleEnabled") private var cloudBackupEnabled = false
    
    private var iCloudBackupToggle: some View {
        SettingsToggleRow(
            title: "Enable iCloud Backup",
            systemImage: "icloud.and.arrow.up",
            color: .cyan,
            isOn: $cloudBackupEnabled
        )
    }
}

#Preview {
    SettingsView()
}
