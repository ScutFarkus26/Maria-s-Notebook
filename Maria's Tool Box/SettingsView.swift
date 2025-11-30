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

    // Export / Import state
    @State private var showingExporter = false
    @State private var exportData: Data? = nil
    @State private var showingImporter = false
    @State private var importError: String? = nil
    @State private var showRestoreConfirm = false
    @State private var showingDuplicatesPreview = false
    @State private var maintenanceAlert: (title: String, message: String)? = nil

    // Persist last backup time
    @AppStorage("lastBackupTimeInterval") private var lastBackupTimeInterval: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SettingsGroup(title: "Database Overview", systemImage: "rectangle.grid.2x2") {
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
                                     value: "\(studentLessons.filter { $0.givenAt == nil }.count)",
                                     subtitle: nil,
                                     systemImage: "books.vertical.fill")

                            StatCard(title: "Lessons Given",
                                     value: "\(studentLessons.filter { $0.givenAt != nil }.count)",
                                     subtitle: nil,
                                     systemImage: "checkmark.circle.fill")
                        }
                    }

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
                                            showingImporter = true
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("This will replace your current data with the backup file.")
                                    }
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

                // Begin security-scoped access if needed (macOS sandbox / file providers)
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if needsAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                try BackupManager.restore(from: data, using: modelContext)
                importError = nil
                lastBackupTimeInterval = Date().timeIntervalSinceReferenceDate
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
    }

    // MARK: - Helpers

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
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

#Preview {
    SettingsView()
}

