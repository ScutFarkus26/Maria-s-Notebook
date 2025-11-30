import SwiftUI
import SwiftData

struct StudentImportPreviewView: View {
    let parsed: StudentCSVImporter.Parsed
    let onCancel: () -> Void
    let onConfirm: (StudentCSVImporter.Parsed) -> Void

    @State private var showWarnings: Bool = true
    @State private var includedRows: [StudentCSVImporter.Row] = []

    init(parsed: StudentCSVImporter.Parsed, onCancel: @escaping () -> Void, onConfirm: @escaping (StudentCSVImporter.Parsed) -> Void) {
        self.parsed = parsed
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _includedRows = State(initialValue: parsed.rows)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Import Students Preview")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection

                    if !parsed.warnings.isEmpty {
                        warningsSection
                    }

                    listSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Import (\(includedRows.count))") { onConfirm(filteredParsed()) }
                    .buttonStyle(.borderedProminent)
                    .disabled(includedRows.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                stat("Total Rows", value: "\(parsed.totalRows)")
                stat("Will Insert/Update", value: "\(includedRows.count)")
                stat("Potential Duplicates", value: "\(parsed.potentialDuplicates.count)")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Warnings", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.yellow)
                Spacer()
                Button(action: { withAnimation { showWarnings.toggle() } }) {
                    Image(systemName: showWarnings ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showWarnings {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parsed.warnings.indices, id: \.self) { i in
                        Text("• \(parsed.warnings[i])")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Students to Import")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if includedRows.isEmpty {
                    Text("No rows selected for import. Remove filters or close to cancel.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(includedRows.enumerated()), id: \.offset) { pair in
                        let i = pair.offset
                        let r = pair.element
                        StudentRowView(row: r, isPotentialDuplicate: isPotentialDuplicate(row: r), onRemove: {
                            withAnimation { includedRows.removeSubrange(i...i) }
                        })
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func isPotentialDuplicate(row: StudentCSVImporter.Row) -> Bool {
        let name = "\(row.firstName) \(row.lastName)"
        return parsed.potentialDuplicates.contains(name)
    }

    private func filteredParsed() -> StudentCSVImporter.Parsed {
        let filteredDuplicateNames: [String] = includedRows.compactMap { row in
            let name = "\(row.firstName) \(row.lastName)"
            return parsed.potentialDuplicates.contains(name) ? name : nil
        }
        return StudentCSVImporter.Parsed(rows: includedRows, totalRows: includedRows.count, potentialDuplicates: filteredDuplicateNames, warnings: parsed.warnings)
    }
}

private struct StudentRowView: View {
    let row: StudentCSVImporter.Row
    let isPotentialDuplicate: Bool
    let onRemove: (() -> Void)?

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(row.firstName) \(row.lastName)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if isPotentialDuplicate {
                    Label("Potential duplicate", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.yellow)
                        .help("A student with the same name and birthday (if provided) already exists.")
                }
                Spacer()
                HStack(spacing: 8) {
                    if let lvl = row.level {
                        Text(lvl.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    if let b = row.birthday {
                        Text("DOB: \(dateFormatter.string(from: b))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    if let ds = row.dateStarted {
                        Text("Start: \(dateFormatter.string(from: ds))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    if let onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Exclude this row from import")
                    }
                }
            }
        }
    }
}
#Preview {
    let rows = [
        StudentCSVImporter.Row(firstName: "Alex", lastName: "Rivera", birthday: Date(timeIntervalSince1970: 0), dateStarted: Date(timeIntervalSince1970: 100000), level: .upper),
        StudentCSVImporter.Row(firstName: "Blair", lastName: "Chen", birthday: nil, dateStarted: nil, level: .lower)
    ]
    let parsed = StudentCSVImporter.Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: ["Alex Rivera"], warnings: ["Row 4: Missing first or last name; row skipped."])
    return StudentImportPreviewView(parsed: parsed, onCancel: {}, onConfirm: { _ in })
}

