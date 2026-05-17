import SwiftUI
import CoreData

struct LessonImportPreviewView: View {
    let parsed: LessonCSVImporter.Parsed
    let onCancel: () -> Void
    let onConfirm: (LessonCSVImporter.Parsed) -> Void

    @State private var showWarnings: Bool = true
    @State private var includedRows: [LessonCSVImporter.Row] = []

    init(
        parsed: LessonCSVImporter.Parsed,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (LessonCSVImporter.Parsed) -> Void
    ) {
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
                    .font(AppTheme.ScaledFont.titleMedium)
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
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                stat("Total Rows", value: "\(parsed.totalRows)")
                stat("Will Insert", value: "\(includedRows.count)")
                stat("Potential Duplicates", value: "\(parsed.potentialDuplicates.count)")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
            )
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTheme.ScaledFont.calloutBold)
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
                Button(action: { adaptiveWithAnimation { showWarnings.toggle() } }, label: {
                    Image(systemName: showWarnings ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                })
                .buttonStyle(.plain)
            }

            if showWarnings {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parsed.warnings.indices, id: \.self) { i in
                        Text("• \(parsed.warnings[i])")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(UIConstants.OpacityConstants.subtle))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.yellow.opacity(UIConstants.OpacityConstants.quarter), lineWidth: 1)
                )
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lessons to Import")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if includedRows.isEmpty {
                    Text("No rows selected for import. Remove filters or close to cancel.")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(includedRows.enumerated()), id: \.offset) { pair in
                        let i = pair.offset
                        let r = pair.element
                        LessonRowView(row: r, isPotentialDuplicate: isPotentialDuplicate(row: r), onRemove: {
                            adaptiveWithAnimation { includedRows.removeSubrange(i...i) }
                        })
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func isPotentialDuplicate(row: LessonCSVImporter.Row) -> Bool {
        let groupStr = row.sequence
        let title = groupStr.isEmpty ? "\(row.name) — \(row.area)" : "\(row.name) — \(row.area) • \(groupStr)"
        return parsed.potentialDuplicates.contains(title)
    }

    private func filteredParsed() -> LessonCSVImporter.Parsed {
        let filteredDuplicateTitles: [String] = includedRows.compactMap { row in
            let groupStr = row.sequence
            let title = groupStr.isEmpty
                ? "\(row.name) — \(row.area)"
                : "\(row.name) — \(row.area) • \(groupStr)"
            return parsed.potentialDuplicates.contains(title) ? title : nil
        }
        return LessonCSVImporter.Parsed(
            rows: includedRows, totalRows: parsed.totalRows,
            potentialDuplicates: filteredDuplicateTitles,
            warnings: parsed.warnings
        )
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
                    .font(AppTheme.ScaledFont.bodySemibold)
                if isPotentialDuplicate {
                    Label("Potential duplicate", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.yellow)
                        .help("A lesson with the same name/area/sequence already exists.")
                }
                Spacer()
                HStack(spacing: 8) {
                    areaBadge
                    if let order = row.orderInSequence {
                        Text("#\(order)")
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                            )
                    }
                    if let onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.destructive)
                        }
                        .buttonStyle(.plain)
                        .help("Exclude this row from import")
                    }
                }
            }

            if !row.sequence.isEmpty || !row.section.isEmpty {
                HStack(spacing: 8) {
                    if !row.sequence.isEmpty {
                        Text(row.sequence)
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.tint).opacity(UIConstants.OpacityConstants.medium))
                    }
                    if !row.section.isEmpty {
                        Text(row.section)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !row.writeUp.isEmpty {
                Text(row.writeUp)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var areaBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(.tint).frame(width: 6, height: 6)
            Text(row.area)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.tint).opacity(UIConstants.OpacityConstants.medium))
    }
}

#Preview {
    let rows = [
        LessonCSVImporter.Row(
            name: "The Story of Numerals", area: "Math",
            sequence: "Introduction", section: "",
            writeUp: "A foundational story.", orderInSequence: nil,
            materials: "", purpose: "", ageRange: "", teacherNotes: ""
        ),
        LessonCSVImporter.Row(
            name: "Introduce the Materials", area: "Math",
            sequence: "Wooden Hierarchal Materials", section: "",
            writeUp: "", orderInSequence: nil,
            materials: "", purpose: "", ageRange: "", teacherNotes: ""
        ),
        LessonCSVImporter.Row(
            name: "Three Period Lesson and Layered Layout",
            area: "Math",
            sequence: "Wooden Hierarchal Materials", section: "",
            writeUp: "", orderInSequence: nil,
            materials: "", purpose: "", ageRange: "", teacherNotes: ""
        )
    ]
    let parsed = LessonCSVImporter.Parsed(
        rows: rows, totalRows: rows.count,
        potentialDuplicates: ["The Story of Numerals — Math"],
        warnings: ["Row 4: Missing required Name or Area; row skipped."]
    )
    LessonImportPreviewView(parsed: parsed, onCancel: {}, onConfirm: { _ in })
}
