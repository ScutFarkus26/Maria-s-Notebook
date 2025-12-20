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
    @State private var exportData: Data? = nil
    @State private var showingImporter = false
    @State private var importError: String? = nil
    @State private var showRestoreConfirm = false
    @State private var showingDuplicatesPreview = false
    @State private var maintenanceAlert: (title: String, message: String)? = nil
    @State private var pendingImporterPresentation = false

    // Persist last backup time
    @AppStorage("lastBackupTimeInterval") private var lastBackupTimeInterval: Double?
    
//    @AppStorage("showWorkAgendaBeta") private var showWorkAgendaBeta: Bool = false
//    @AppStorage("hideWorksAgendaTab") private var hideWorksAgendaTab: Bool = false
//    @AppStorage("hideLessonsBoardTab") private var hideLessonsBoardTab: Bool = false  // REMOVED as per instructions

    // Removed engagement lifecycle state properties
    // @AppStorage("useEngagementLifecycle") private var useEngagementLifecycle: Bool = false
    // @State private var lifecycleBackfillSummary: String? = nil
    // @State private var showLifecycleNotesBackfillConfirm: Bool = false
    // @State private var isRunningLifecycleBackfill: Bool = false

    // New state properties for Advanced / Debug section
    @State private var showDannyResetConfirm = false
    @State private var dannyResetSummary: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Overview Section
                    SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            StatCard(title: "Students",
                                     value: "\(students.count)",
                                     subtitle: nil,
                                     systemImage: "person.3.fill")

                            StatCard(title: "Lessons",
                                     value: "\(lessons.count)",
                                     subtitle: nil,
                                     systemImage: "text.book.closed.fill")

                            StatCard(title: "Lessons Planned",
                                     value: "\(plannedLessons.count)",
                                     subtitle: nil,
                                     systemImage: "books.vertical.fill")

                            StatCard(title: "Lessons Given",
                                     value: "\(givenLessons.count)",
                                     subtitle: nil,
                                     systemImage: "checkmark.circle.fill")
                        }
                    }
                    
                    // MARK: - Data Management Section
                    SettingsCategoryHeader(title: "Data Management")
                    
                    HStack(alignment: .top, spacing: 24) {
                        // Backup & Restore
                        SettingsGroup(title: "Backup & Restore", systemImage: "arrow.triangle.2.circlepath") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button {
                                        do {
                                            let data = try BackupManager.makeBackupData(using: modelContext)
                                            exportData = data
                                            showingExporter = true
                                        } catch {
                                            importError = "Failed to create backup: \(error.localizedDescription)"
                                        }
                                    } label: {
                                        Label("Create Backup", systemImage: "externaldrive.badge.plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)

                                    Button(role: .destructive) {
                                        showRestoreConfirm = true
                                    } label: {
                                        Label("Restore from Backup", systemImage: "arrow.down.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .tint(.red)
                                    .confirmationDialog(
                                        "Restore from Backup?",
                                        isPresented: $showRestoreConfirm,
                                        titleVisibility: .visible
                                    ) {
                                        Button("Choose Backup File…", role: .destructive) {
                                            pendingImporterPresentation = true
                                            showRestoreConfirm = false
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("This will replace your current data with the backup file.")
                                    }
                                }

                                if UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                                    let reason = UserDefaults.standard.string(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey) ?? "The persistent store could not be opened. Data will not persist this session."
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label {
                                            Text("Warning: Data won't persist this session")
                                                .font(.headline)
                                        } icon: {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                        }
                                        Text(reason)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Button {
                                            NotificationCenter.default.post(name: Notification.Name("CreateBackupRequested"), object: nil)
                                        } label: {
                                            Label("Create Backup Now", systemImage: "externaldrive.badge.plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                if let lastBackupDate = lastBackupDate {
                                    Label {
                                        Text("Last backup: \(lastBackupDate, style: .relative)")
                                    } icon: {
                                        Image(systemName: "clock")
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                } else {
                                    Label("Last backup: Never", systemImage: "clock")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }

                                if let importError {
                                    Text(importError)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Maintenance
                        SettingsGroup(title: "Maintenance", systemImage: "wrench.and.screwdriver") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button {
                                        do {
                                            let summary = try StudentDuplicatesCleaner.mergeDuplicates(using: modelContext)
                                            let message = "Groups of Students considered: \(summary.groupsConsidered)\nGroups of Students merged: \(summary.groupsMerged)\nStudents deleted: \(summary.studentsDeleted)\nReferences updated: \(summary.referencesUpdated)"
                                            maintenanceAlert = (title: "Merge Duplicate Students", message: message)
                                        } catch {
                                            maintenanceAlert = (title: "Merge Failed", message: error.localizedDescription)
                                        }
                                    } label: {
                                        Label("Merge Duplicate Students", systemImage: "person.2.crop.square.stack")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)

                                    Button {
                                        showingDuplicatesPreview = true
                                    } label: {
                                        Label("Preview Duplicates…", systemImage: "list.bullet.rectangle.portrait")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                }

                                Text("Housekeeping tools to keep your data tidy.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // MARK: - School Configuration Section
                    SettingsCategoryHeader(title: "School Configuration")
                    
                    SettingsGroup(title: "School Calendar", systemImage: "calendar.badge.exclamationmark") {
                        SchoolCalendarSettingsView()
                            .frame(maxWidth: .infinity)
                    }
                    
                    // MARK: - Attendance Section
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
                    
                    // MARK: - Advanced / Debug Section (added)
                    SettingsCategoryHeader(title: "Advanced / Debug")
                    
                    SettingsGroup(title: "Danger Zone", systemImage: "exclamationmark.triangle.fill") {
                        Button(role: .destructive) {
                            showDannyResetConfirm = true
                        } label: {
                            Label("Delete Lesson & Work History for Danny + Lil Dan D", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
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
            contentType: .json,
            defaultFilename: defaultBackupFilename()
        ) { result in
            switch result {
            case .success:
                lastBackupTimeInterval = Date().timeIntervalSinceReferenceDate
            case .failure(let error):
                importError = "Failed to write backup: \(error.localizedDescription)"
            }
            exportData = nil
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let url = try result.get()

                Task.detached(priority: .userInitiated) {
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try await MainActor.run {
                            try BackupManager.restore(from: data, using: modelContext)
                            importError = nil
                            lastBackupTimeInterval = Date().timeIntervalSinceReferenceDate
                            NotificationCenter.default.post(name: Notification.Name("BackfillIsPresentedRequested"), object: nil)
                        }
                    } catch {
                        await MainActor.run {
                            importError = "Failed to restore: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                importError = "Failed to restore: \(error.localizedDescription)"
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
            do {
                let data = try BackupManager.makeBackupData(using: modelContext)
                exportData = data
                showingExporter = true
            } catch {
                importError = "Failed to create backup: \(error.localizedDescription)"
            }
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
        // New alert showing completion summary
        .alert("History Deleted", isPresented: Binding(get: { dannyResetSummary != nil }, set: { if !$0 { dannyResetSummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dannyResetSummary ?? "")
        }
        .onAppear {
            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            // We infer this by the absence of the in-memory flag being set by App startup code.
            if !UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            }
        }
    }

    // MARK: - Helpers

    private static let backupFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private func defaultBackupFilename() -> String {
        let formatter = SettingsView.backupFilenameFormatter
        return "MariasToolbox_Backup_\(formatter.string(from: Date())).json"
    }

    private var exportDocument: BackupDocument? {
        guard let exportData else { return nil }
        return BackupDocument(data: exportData)
    }

    private var totalNextLessonsCount: Int {
        // Count all student lessons that have not yet been given
        studentLessons.filter { $0.givenAt == nil }.count
    }

    private var lastBackupDate: Date? {
        if let lastBackupTimeInterval {
            return Date(timeIntervalSinceReferenceDate: lastBackupTimeInterval)
        } else {
            return nil
        }
    }
}

// MARK: - FileDocument wrapper for exporting JSON
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let file = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Visual components replicated from the reference style
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

struct SettingsCategoryHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    private var groupBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, systemImage: systemImage)
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(groupBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }
}

struct SchoolCalendarSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @State private var currentMonth: Date = Date()
    @State private var selected: Set<DateComponents> = []
    @State private var nonSchoolDates: Set<Date> = []
    @State private var selectedSingleDate: Date = Date()

    private var monthInterval: DateInterval {
        let cal = calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? Date()
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text(monthTitle(currentMonth))
                    .font(.headline)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                Spacer()
                Label("Tap dates to mark as non-school", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CalendarMonthGridView(
                month: currentMonth,
                onDateToggled: { date, isNonSchool in
                    let day = calendar.startOfDay(for: date)
                    if isNonSchool {
                        nonSchoolDates.insert(day)
                    } else {
                        nonSchoolDates.remove(day)
                    }
                },
                nonSchoolDates: nonSchoolDates
            )

            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    clearMonth()
                } label: {
                    Label("Clear this month", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button {
                    markWeekdaysAsSchoolDays()
                } label: {
                    Label("Keep weekends only", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Text("These dates will be treated as non-school days across planning and attendance.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear { reload() }
    }

    private func reload() {
        let range = monthInterval.start ..< monthInterval.end
        nonSchoolDates = SchoolCalendar.nonSchoolDays(in: range, using: modelContext)
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = newDate
            reload()
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return df.string(from: date)
    }

    private func clearMonth() {
        let cal = calendar
        var d = cal.startOfDay(for: monthInterval.start)
        while d < monthInterval.end {
            let descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
            if let arr = try? modelContext.fetch(descriptor), let existing = arr.first {
                modelContext.delete(existing)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        reload()
    }

    private func markWeekdaysAsSchoolDays() {
        // Unmark weekends only for the current month: keep Sat/Sun marked; unmark weekdays
        let cal = calendar
        var d = cal.startOfDay(for: monthInterval.start)
        while d < monthInterval.end {
            let weekday = cal.component(.weekday, from: d)
            if weekday != 1 && weekday != 7 { // 1=Sun, 7=Sat
                // ensure weekdays are not marked as non-school
                let descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
                let items = (try? modelContext.fetch(descriptor)) ?? []
                if let existing = items.first {
                    modelContext.delete(existing)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        reload()
    }
}

struct PresentNowSettingsView: View {
    @AppStorage("StudentsView.presentNow.excludedNames") private var presentNowExcludedNamesRaw: String = "danny de berry,lil dan d"
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude names from ‘Present Now’")
                .font(.headline)
            Text("Enter a comma or semicolon separated list of full names to exclude from the Present Now filter. Matching is case-insensitive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: AppTheme.FontSize.body))
                .frame(minHeight: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                )
            HStack {
                Spacer()
                Button("Restore Default") {
                    draft = "danny de berry,lil dan d"
                }
                Button("Save") {
                    presentNowExcludedNamesRaw = draft
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { draft = presentNowExcludedNamesRaw }
    }
}

struct LessonAgeSettingsView: View {
    @AppStorage("LessonAge.warningDays") private var warningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("LessonAge.overdueDays") private var overdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("LessonAge.freshColorHex") private var freshHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("LessonAge.warningColorHex") private var warningHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("LessonAge.overdueColorHex") private var overdueHex: String = LessonAgeDefaults.overdueColorHex

    @State private var freshColor: Color = ColorUtils.color(from: LessonAgeDefaults.freshColorHex)
    @State private var warningColor: Color = ColorUtils.color(from: LessonAgeDefaults.warningColorHex)
    @State private var overdueColor: Color = ColorUtils.color(from: LessonAgeDefaults.overdueColorHex)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure thresholds and colors for the lesson age indicator in Planning → Agenda.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Stepper(value: $warningDays, in: 0...30) {
                    Text("Warning starts at \(warningDays) school day\(warningDays == 1 ? "" : "s")")
                }
                Stepper(value: $overdueDays, in: 1...60) {
                    Text("Overdue after \(overdueDays) school day\(overdueDays == 1 ? "" : "s")")
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Fresh Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Fresh", selection: Binding(get: { freshColor }, set: { new in
                        freshColor = new
                        freshHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Warning Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Warning", selection: Binding(get: { warningColor }, set: { new in
                        warningColor = new
                        warningHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Overdue Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Overdue", selection: Binding(get: { overdueColor }, set: { new in
                        overdueColor = new
                        overdueHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
            }
        }
        .onAppear {
            // Initialize pickers from stored hex strings
            freshColor = ColorUtils.color(from: freshHex)
            warningColor = ColorUtils.color(from: warningHex)
            overdueColor = ColorUtils.color(from: overdueHex)
        }
    }
}

struct WorkAgeSettingsView: View {
    @AppStorage("WorkAge.warningDays") private var warningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("WorkAge.overdueDays") private var overdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("WorkAge.freshColorHex") private var freshHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("WorkAge.warningColorHex") private var warningHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("WorkAge.overdueColorHex") private var overdueHex: String = LessonAgeDefaults.overdueColorHex

    @State private var freshColor: Color = ColorUtils.color(from: LessonAgeDefaults.freshColorHex)
    @State private var warningColor: Color = ColorUtils.color(from: LessonAgeDefaults.warningColorHex)
    @State private var overdueColor: Color = ColorUtils.color(from: LessonAgeDefaults.overdueColorHex)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure thresholds and colors for the work age indicator in Planning → Work Agenda.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Stepper(value: $warningDays, in: 0...30) {
                    Text("Warning starts at \(warningDays) school day\(warningDays == 1 ? "" : "s")")
                }
                Stepper(value: $overdueDays, in: 1...60) {
                    Text("Overdue after \(overdueDays) school day\(overdueDays == 1 ? "" : "s")")
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Fresh Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Fresh", selection: Binding(get: { freshColor }, set: { new in
                        freshColor = new
                        freshHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Warning Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Warning", selection: Binding(get: { warningColor }, set: { new in
                        warningColor = new
                        warningHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Overdue Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Overdue", selection: Binding(get: { overdueColor }, set: { new in
                        overdueColor = new
                        overdueHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
            }
        }
        .onAppear {
            // Initialize pickers from stored hex strings
            freshColor = ColorUtils.color(from: freshHex)
            warningColor = ColorUtils.color(from: warningHex)
            overdueColor = ColorUtils.color(from: overdueHex)
        }
    }
}

#Preview {
    SettingsView()
}

