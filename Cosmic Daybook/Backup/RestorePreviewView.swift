import SwiftUI

public struct RestorePreviewView: View {
    public let preview: RestorePreview
    public let onCancel: () -> Void
    public let onConfirm: () -> Void

    public init(preview: RestorePreview, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.preview = preview
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        totalsSection
                        entityBreakdownSection
                        warningsSection
                    }
                    .padding(16)
                }
                Divider()
                footer
            }
            .navigationTitle("Restore Preview")
            .inlineNavigationTitle()
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're about to restore a backup")
                    .font(.headline)
                Text(modeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var modeDescription: String {
        let mode = preview.mode.lowercased()
        if mode == "replace" {
            return "Replace: everything in your notebook is removed and replaced by what's in the backup."
        } else {
            return "Merge: what's in the backup is added, and anything already here is updated to match it. "
                + "Nothing else changes."
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totals")
                .font(.headline)
            HStack(spacing: 16) {
                Label("Adding: \(preview.totalInserts)", systemImage: "plus.circle.fill")
                    .foregroundStyle(AppColors.success)
                Label("Removing: \(preview.totalDeletes)", systemImage: "trash.fill")
                    .foregroundStyle(preview.totalDeletes > 0 ? AppColors.destructive : .secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }

    private var entityBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What changes")
                .font(.headline)
            let keys = allEntityKeys.sorted()
            if keys.isEmpty {
                Text("Nothing would change.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 12) {
                        Text(key)
                            .font(.subheadline)
                            .frame(width: 200, alignment: .leading)
                        let ins = inserts[key] ?? 0
                        let sk = skips[key] ?? 0
                        let del = deletes[key] ?? 0
                        if ins > 0 { chip(text: "+\(ins)", color: .green, system: "plus") }
                        // Already in the notebook: a merge updates them to match the backup.
                        if sk > 0 {
                            chip(text: "already here \(sk)", color: .secondary, system: "arrow.triangle.2.circlepath")
                        }
                        if del > 0 { chip(text: "-\(del)", color: .red, system: "trash") }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private var warningsSection: some View {
        Group {
            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Warnings")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(BackupWarningText.plain(preview.warnings), id: \.self) { w in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(w)
                                    .font(.subheadline)
                            }
                        }
                        TechnicalDetailsDisclosure(details: BackupWarningText.details(preview.warnings))
                    }
                    .padding(8)
                    .surface(
                        UIConstants.CornerRadius.medium,
                        fill: Color.yellow.opacity(UIConstants.OpacityConstants.subtle),
                        style: .continuous
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(role: .cancel) {
                onCancel()
            } label: {
                Text("Cancel")
            }
            Spacer()
            Button(role: .none) {
                onConfirm()
            } label: {
                Label("Restore Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // The counts under their plain names ("Planned lessons", not "LessonAssignment").
    private var inserts: [String: Int] { BackupPlainNames.grouped(preview.entityInserts) }
    private var skips: [String: Int] { BackupPlainNames.grouped(preview.entitySkips) }
    private var deletes: [String: Int] { BackupPlainNames.grouped(preview.entityDeletes) }

    /// The kinds with something to add, update or remove; one with nothing either way isn't a change.
    private var allEntityKeys: Set<String> {
        Set(inserts.keys).union(skips.keys).union(deletes.keys).filter { key in
            (inserts[key] ?? 0) + (skips[key] ?? 0) + (deletes[key] ?? 0) > 0
        }
    }

    private func chip(text: String, color: Color, system: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .capsuleFill(color.opacity(UIConstants.OpacityConstants.medium), style: .continuous)
        .foregroundStyle(color)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module, so its body lives in a private view that is checked once.
private struct RestorePreviewViewPreview: View {
    var body: some View {
        let preview = RestorePreview(
            mode: "merge",
            entityInserts: ["Student": 3, "Lesson": 1, "LessonAssignment": 4],
            entitySkips: ["Student": 2, "Lesson": 0, "LessonAssignment": 1],
            entityDeletes: ["Student": 0, "Lesson": 0, "LessonAssignment": 0],
            totalInserts: 8,
            totalDeletes: 0,
            warnings: [
                "1 lesson assignments reference lessons missing from both this backup and the library; "
                    + "they will be restored but stay unlinked until their lesson exists."
            ]
        )
        return RestorePreviewView(preview: preview, onCancel: {}, onConfirm: {})
    }
}

#Preview("Restore Preview") {
    RestorePreviewViewPreview()
}
