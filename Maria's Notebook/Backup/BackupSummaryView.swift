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
        case .export: return "Backup Export Complete"
        case .import: return "Backup Import Complete"
        }
    }

    private var createdAtString: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: summary.createdAt)
    }

    private var filteredCounts: [(String, Int)] {
        let filtered = summary.entityCounts.filter { key, count in
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3).bold()
                Spacer()
            }
            HStack(spacing: 12) {
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Picker("Sort", selection: $sortMode) {
                    Text("Name").tag(0)
                    Text("Count").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                Toggle("Show zeros", isOn: $showZeros)
                    .toggleStyle(.switch)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File: \(summary.fileName)")
                    Text("Format Version: \(summary.formatVersion)")
                    Text("Encryption: \(summary.encryptUsed ? "On" : "Off")")
                    Text("Created: \(createdAtString)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Records")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredCounts, id: \.0) { key, count in
                        HStack {
                            Text(key)
                            Spacer()
                            Text("\(count)")
                                .bold()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if !summary.warnings.isEmpty {
                Button(action: {
                    withAnimation {
                        warningsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Warnings")
                            .font(.headline)
                        Spacer()
                        Text("\(summary.warnings.count)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        Image(systemName: warningsExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                if warningsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.warnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                Text(w)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
    }
}

#Preview {
    BackupSummaryView(summary: BackupOperationSummary(kind: .export, fileName: "sample.mtbbackup", formatVersion: 2, encryptUsed: true, createdAt: Date(), entityCounts: ["students": 24, "lessons": 180], warnings: ["Files/attachments are not included in backups by design."]))
}
