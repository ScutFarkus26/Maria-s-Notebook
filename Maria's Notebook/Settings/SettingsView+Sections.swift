import SwiftUI
import SwiftData

// MARK: - SettingsView Section Builders

extension SettingsView {

    // MARK: - Pane Content Router

    @ViewBuilder
    func settingsPaneContent(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            generalSection
        case .dataSync:
            dataSyncSection
        case .backup:
            backupManagementSection
        case .templates:
            templatesSection
        case .communication:
            communicationSection
        case .aiFeatures:
            aiFeaturesSection
        case .database:
            databaseSection
        case .advanced:
            advancedSection
        }
    }

    // MARK: - Section Definitions

    // 1. General
    var generalSection: some View {
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

    // 2. Data & Sync
    var dataSyncSection: some View {
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

    // 3. Backup & Data Management
    var backupManagementSection: some View {
        DataManagementGrid()
    }

    // 4. Templates
    var templatesSection: some View {
        VStack(spacing: 12) {
            SettingsGroup(title: "Note Templates", systemImage: "note.text.badge.plus") {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(statsViewModel.noteTemplatesCount)")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
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
                                .foregroundStyle(.primary)
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

    // 5. Communication
    var communicationSection: some View {
        SettingsGroup(title: "Attendance Email", systemImage: "checkmark.circle.fill") {
            AttendanceEmailSettingsView()
                .frame(maxWidth: .infinity)
        }
    }

    // 6. AI Features
    var aiFeaturesSection: some View {
        VStack(spacing: 12) {
            SettingsGroup(title: "AI Models", systemImage: "cpu") {
                AIModelSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(title: "Apple Intelligence", systemImage: "apple.logo") {
                appleIntelligenceStatus
            }

            SettingsGroup(title: "Ollama", systemImage: "server.rack") {
                OllamaSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(title: "Claude API Key", systemImage: "key.fill") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Anthropic API")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if AnthropicAPIClient.hasAPIKey() {
                                Label("API key configured", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.success)
                            } else {
                                Label("API key required for Claude models", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.warning)
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

            SettingsGroup(title: "Lesson Planning Assistant", systemImage: "list.clipboard") {
                LessonPlanningSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 7. Database
    var databaseSection: some View {
        SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
            VStack(spacing: 16) {
                DatabaseTotalSummary(totalRecords: statsViewModel.totalRecordsCount)

                DatabaseStatsSubsection(
                    title: "Teaching",
                    systemImage: "book.fill",
                    summaryValue: "\(statsViewModel.teachingTotal) records"
                ) {
                    LazyVGrid(columns: overviewColumns, spacing: 16) {
                        StatCard(
                            title: "Students", value: "\(statsViewModel.studentsCount)",
                            subtitle: nil, systemImage: "person.3.fill"
                        )
                        StatCard(
                            title: "Lessons", value: "\(statsViewModel.lessonsCount)",
                            subtitle: nil, systemImage: "text.book.closed.fill"
                        )
                        StatCard(
                            title: "Lessons Planned", value: "\(statsViewModel.plannedCount)",
                            subtitle: nil, systemImage: "books.vertical.fill"
                        )
                        StatCard(
                            title: "Lessons Given", value: "\(statsViewModel.givenCount)",
                            subtitle: nil, systemImage: "checkmark.circle.fill"
                        )
                        StatCard(
                            title: "Work Items", value: "\(statsViewModel.workModelsCount)",
                            subtitle: "Assigned", systemImage: "doc.text.fill"
                        )
                        StatCard(
                            title: "Presentations", value: "\(statsViewModel.presentationsCount)",
                            subtitle: "History", systemImage: "paintpalette.fill"
                        )
                        StatCard(
                            title: "Observations", value: "\(statsViewModel.notesCount)",
                            subtitle: "Notes", systemImage: "note.text"
                        )
                        StatCard(
                            title: "Meetings", value: "\(statsViewModel.meetingsCount)",
                            subtitle: "Records", systemImage: "person.2.fill"
                        )
                        StatCard(
                            title: "Practice", value: "\(statsViewModel.practiceSessionsCount)",
                            subtitle: "Sessions", systemImage: "music.note.list"
                        )
                    }
                }

                DatabaseStatsSubsection(
                    title: "Planning",
                    systemImage: "checklist",
                    summaryValue: "\(statsViewModel.planningTotal) records"
                ) {
                    LazyVGrid(columns: overviewColumns, spacing: 16) {
                        StatCard(
                            title: "To-Do Items", value: "\(statsViewModel.todoItemsCount)",
                            subtitle: "\(statsViewModel.todoCompletedCount) completed",
                            systemImage: "checklist"
                        )
                        StatCard(
                            title: "Reminders", value: "\(statsViewModel.remindersCount)",
                            subtitle: "Synced", systemImage: "bell.fill"
                        )
                        StatCard(
                            title: "Tracks", value: "\(statsViewModel.tracksCount)",
                            subtitle: "\(statsViewModel.trackEnrollmentsCount) enrollments",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill"
                        )
                        StatCard(
                            title: "Calendar Events",
                            value: "\(statsViewModel.calendarEventsCount)",
                            subtitle: "Events", systemImage: "calendar"
                        )
                        StatCard(
                            title: "Projects", value: "\(statsViewModel.projectsCount)",
                            subtitle: nil, systemImage: "folder.fill"
                        )
                    }
                }

                DatabaseStatsSubsection(
                    title: "Classroom",
                    systemImage: "building.2.fill",
                    summaryValue: "\(statsViewModel.classroomTotal) records"
                ) {
                    LazyVGrid(columns: overviewColumns, spacing: 16) {
                        StatCard(
                            title: "Attendance",
                            value: "\(statsViewModel.attendanceRecordsCount)",
                            subtitle: "Records", systemImage: "checkmark.square.fill"
                        )
                        StatCard(
                            title: "Supplies", value: "\(statsViewModel.suppliesCount)",
                            subtitle: "Items", systemImage: "shippingbox.fill"
                        )
                        StatCard(
                            title: "Issues", value: "\(statsViewModel.issuesCount)",
                            subtitle: "\(statsViewModel.issuesResolvedCount) resolved",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        StatCard(
                            title: "Community",
                            value: "\(statsViewModel.communityTopicsCount)",
                            subtitle: "Topics",
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                        StatCard(
                            title: "Procedures",
                            value: "\(statsViewModel.proceduresCount)",
                            subtitle: nil, systemImage: "list.clipboard.fill"
                        )
                        StatCard(
                            title: "Non-School Days",
                            value: "\(statsViewModel.nonSchoolDaysCount)",
                            subtitle: "Configured",
                            systemImage: "calendar.badge.minus"
                        )
                    }
                }

                DatabaseStatsSubsection(
                    title: "Storage & Templates",
                    systemImage: "archivebox.fill",
                    summaryValue: "\(statsViewModel.storageTotal) records"
                ) {
                    LazyVGrid(columns: overviewColumns, spacing: 16) {
                        StatCard(
                            title: "Documents",
                            value: "\(statsViewModel.documentsCount)",
                            subtitle: "Files", systemImage: "doc.fill"
                        )
                        StatCard(
                            title: "Lesson Files",
                            value: "\(statsViewModel.lessonAttachmentsCount)",
                            subtitle: "Attachments",
                            systemImage: "paperclip"
                        )
                        StatCard(
                            title: "Community Files",
                            value: "\(statsViewModel.communityAttachmentsCount)",
                            subtitle: "Attachments",
                            systemImage: "paperclip.badge.ellipsis"
                        )
                        StatCard(
                            title: "Note Templates",
                            value: "\(statsViewModel.noteTemplatesCount)",
                            subtitle: nil,
                            systemImage: "note.text.badge.plus"
                        )
                        StatCard(
                            title: "Meeting Templates",
                            value: "\(statsViewModel.meetingTemplatesCount)",
                            subtitle: nil, systemImage: "person.2.fill"
                        )
                        StatCard(
                            title: "To-Do Templates",
                            value: "\(statsViewModel.todoTemplatesCount)",
                            subtitle: nil, systemImage: "checklist"
                        )
                        StatCard(
                            title: "Dev Snapshots",
                            value: "\(statsViewModel.developmentSnapshotsCount)",
                            subtitle: "Analytics",
                            systemImage: "camera.viewfinder"
                        )
                    }
                }
            }
        }
    }

    // 8. Advanced (Debug Only -- hidden in release via visibleCategories filter)
    var advancedSection: some View {
        SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
            #if DEBUG
            TestStudentsSettingsView()
                .frame(maxWidth: .infinity)
            #else
            Text("Advanced settings are only available in debug builds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    // MARK: - Apple Intelligence Status

    @ViewBuilder
    var appleIntelligenceStatus: some View {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            AppleIntelligenceStatusRow()
        } else {
            appleIntelligenceUnavailableView
        }
        #else
        appleIntelligenceUnavailableView
        #endif
    }

    var appleIntelligenceUnavailableView: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Not Available")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(AppColors.warning)
                Text("Requires macOS 26 or iOS 26 with Apple Intelligence enabled")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // iCloud Backup Toggle
    var iCloudBackupToggle: some View {
        SettingsToggleRow(
            title: "Enable iCloud Backup",
            systemImage: "icloud.and.arrow.up",
            color: .cyan,
            isOn: $cloudBackupEnabled
        )
    }
}
