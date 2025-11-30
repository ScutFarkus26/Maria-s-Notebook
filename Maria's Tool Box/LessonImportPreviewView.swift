import SwiftUI
import SwiftData

struct LessonImportPreviewView: View {
    let parsed: LessonCSVImporter.Parsed
    let onCancel: () -> Void
    let onConfirm: (LessonCSVImporter.Parsed) -> Void

    @State private var showWarnings: Bool = true
    @State private var includedRows: [LessonCSVImporter.Row] = []

    init(parsed: LessonCSVImporter.Parsed, onCancel: @escaping () -> Void, onConfirm: @escaping (LessonCSVImporter.Parsed) -> Void) {
        self.parsed = parsed
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _includedRows = State(initialValue: parsed.rows)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Import Preview")
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
                stat("Will Insert", value: "\(includedRows.count)")
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
            Text("Lessons to Import")
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
                        LessonRowView(row: r, isPotentialDuplicate: isPotentialDuplicate(row: r), onRemove: {
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

    private func isPotentialDuplicate(row: LessonCSVImporter.Row) -> Bool {
        let groupStr = row.group
        let title = groupStr.isEmpty ? "\(row.name) — \(row.subject)" : "\(row.name) — \(row.subject) • \(groupStr)"
        return parsed.potentialDuplicates.contains(title)
    }

    private func filteredParsed() -> LessonCSVImporter.Parsed {
        let filteredDuplicateTitles: [String] = includedRows.compactMap { row in
            let groupStr = row.group
            let title = groupStr.isEmpty ? "\(row.name) — \(row.subject)" : "\(row.name) — \(row.subject) • \(groupStr)"
            return parsed.potentialDuplicates.contains(title) ? title : nil
        }
        return LessonCSVImporter.Parsed(rows: includedRows, totalRows: parsed.totalRows, potentialDuplicates: filteredDuplicateTitles, warnings: parsed.warnings)
    }
}

private struct LessonRowView: View {
    let row: LessonCSVImporter.Row
    let isPotentialDuplicate: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if isPotentialDuplicate {
                    Label("Potential duplicate", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.yellow)
                        .help("A lesson with the same name/subject/group already exists.")
                }
                Spacer()
                HStack(spacing: 8) {
                    subjectBadge
                    if let order = row.orderInGroup {
                        Text("#\(order)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                            )
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

            if !row.group.isEmpty || !row.subheading.isEmpty {
                HStack(spacing: 8) {
                    if !row.group.isEmpty {
                        Text(row.group)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.tint).opacity(0.12))
                    }
                    if !row.subheading.isEmpty {
                        Text(row.subheading)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !row.writeUp.isEmpty {
                Text(row.writeUp)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var subjectBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(.tint).frame(width: 6, height: 6)
            Text(row.subject)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.tint).opacity(0.12))
    }
}

#Preview {
    let rows = [
        LessonCSVImporter.Row(name: "The Story of Numerals", subject: "Math", group: "Introduction", subheading: "", writeUp: "A foundational story.", orderInGroup: nil),
        LessonCSVImporter.Row(name: "Introduce the Materials", subject: "Math", group: "Wooden Hierarchal Materials", subheading: "", writeUp: "", orderInGroup: nil),
        LessonCSVImporter.Row(name: "Three Period Lesson and Layered Layout", subject: "Math", group: "Wooden Hierarchal Materials", subheading: "", writeUp: "", orderInGroup: nil),
    ]
    let parsed = LessonCSVImporter.Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: ["The Story of Numerals — Math"], warnings: ["Row 4: Missing required Name or Subject; row skipped."])
    return LessonImportPreviewView(parsed: parsed, onCancel: {}, onConfirm: { _ in })
}
