import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Live data for stats
    @Query private var students: [Student]
    @Query private var items: [Item]

    // Export / Import state
    @State private var showingExporter = false
    @State private var exportData: Data? = nil
    @State private var showingImporter = false
    @State private var importError: String? = nil
    @State private var showRestoreConfirm = false

    // Persist last backup time
    @AppStorage("lastBackupTimeInterval") private var lastBackupTimeInterval: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Database Overview
                    SettingsGroup(title: "Database Overview", systemImage: "rectangle.grid.2x2") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            StatCard(title: "Students",
                                     value: "\(students.count)",
                                     subtitle: "total",
                                     systemImage: "person.3.fill")

                            StatCard(title: "Items",
                                     value: "\(items.count)",
                                     subtitle: "records",
                                     systemImage: "square.stack.3d.up.fill")

                            StatCard(title: "Next Lessons",
                                     value: "\(totalNextLessonsCount)",
                                     subtitle: "scheduled",
                                     systemImage: "books.vertical.fill")
                        }
                    }

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

                                Button(role: .destructive) {
                                    showRestoreConfirm = true
                                } label: {
                                    Label("Restore from Backup", systemImage: "arrow.down.doc")
                                }
                                .buttonStyle(.bordered)
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
                                    Text("Last backup: ") + Text(lastBackupDate, style: .relative)
                                } icon: {
                                    Image(systemName: "clock")
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            } else {
                                Label("Last backup: Never", systemImage: "clock")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if let importError {
                                Text(importError)
                                    .foregroundStyle(.red)
                            }
                        }
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
                let data = try Data(contentsOf: url)
                try BackupManager.restore(from: data, using: modelContext)
                importError = nil
            } catch {
                importError = "Failed to restore: \(error.localizedDescription)"
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
        students.reduce(0) { $0 + $1.nextLessons.count }
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
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
