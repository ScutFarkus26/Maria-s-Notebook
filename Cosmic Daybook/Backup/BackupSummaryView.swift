import SwiftUI

struct BackupSummaryView: View {
    let summary: BackupOperationSummary
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var sortMode: Int = 0 // 0 = name, 1 = count
    @State private var showZeros: Bool = false
    @State private var warningsExpanded: Bool = true

    private var title: String {
        switch summary.kind {
        case .export: return "Backup Saved"
        case .import: return "Restore Complete"
        }
    }

    /// The restore's warnings in plain words; the raw ones go under Details.
    private var plainWarnings: [String] { BackupWarningText.plain(summary.warnings) }

    private var createdAtString: String {
        DateFormatters.mediumDateTime.string(from: summary.createdAt)
    }

    /// The counts under their plain names ("Planned lessons", not "LessonAssignment").
    private var filteredCounts: [(String, Int)] {
        let filtered = BackupPlainNames.grouped(summary.entityCounts).filter { key, count in
            (searchText.isEmpty || key.localizedCaseInsensitiveContains(searchText))
                && (showZeros || count != 0)
        }
        let sorted: [(String, Int)]
        switch sortMode {
        case 1:
            sorted = filtered.sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
        default:
            sorted = filtered.sorted { $0.key < $1.key }
        }
        return sorted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            HStack {
                Text(title)
                    .font(.title3).bold()
                Spacer()
            }
            HStack(spacing: SettingsStyle.groupSpacing) {
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Picker("Sort", selection: $sortMode) {
                    Text("Name").tag(0)
                    Text("Count").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                Toggle("Show empty", isOn: $showZeros)
                    .toggleStyle(.switch)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("File: \(summary.fileName)")
                    Text("Encrypted: \(summary.encryptUsed ? "Yes" : "No")")
                    Text("Made: \(createdAtString)")
                    TechnicalDetailsDisclosure(details: "Backup format version \(summary.formatVersion)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("What's in it")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    ForEach(filteredCounts, id: \.0) { key, count in
                        HStack {
                            Text(key)
                            Spacer()
                            Text("\(count)")
                                .bold()
                        }
                        .padding(.vertical, AppTheme.Spacing.xxsmall)
                    }
                }
            }
            ForEach(summary.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !summary.warnings.isEmpty {
                Button(action: {
                    adaptiveWithAnimation {
                        warningsExpanded.toggle()
                    }
                }, label: {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Text("Warnings")
                            .font(.headline)
                        Spacer()
                        Text("\(plainWarnings.count)")
                            .font(.caption2.bold())
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xxsmall)
                            .background(Color.red.opacity(UIConstants.OpacityConstants.heavy))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        Image(systemName: warningsExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                })
                if warningsExpanded {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(plainWarnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                Text(w)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        TechnicalDetailsDisclosure(details: BackupWarningText.details(summary.warnings))
                    }
                    .padding(AppTheme.Spacing.small)
                    .background(.ultraThinMaterial)
                    .clipRounded(AppTheme.Spacing.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(SettingsStyle.padding)
        .frame(minWidth: 420, minHeight: 520)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct BackupSummaryViewPreview: View {
    var body: some View {
        BackupSummaryView(summary: BackupOperationSummary(
            kind: .export,
            fileName: "sample.mtbbackup",
            formatVersion: BackupWriter.formatVersion,
            encryptUsed: true,
            createdAt: Date(),
            entityCounts: ["Student": 24, "Lesson": 180, "LessonAssignment": 312],
            warnings: [],
            notes: [BackupWriter.photoNote(includesPhotos: true, photoCount: 12)]
        ))
    }
}

#Preview {
    BackupSummaryViewPreview()
}
