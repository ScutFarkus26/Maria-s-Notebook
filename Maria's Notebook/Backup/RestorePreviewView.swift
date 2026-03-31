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
                Text("You're about to restore data")
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
            return "Mode: Replace — existing data will be deleted and replaced by the backup."
        } else {
            return "Mode: Merge — new records will be inserted; existing IDs are skipped."
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totals")
                .font(.headline)
            HStack(spacing: 16) {
                Label("Inserts: \(preview.totalInserts)", systemImage: "plus.circle.fill")
                    .foregroundStyle(AppColors.success)
                Label("Deletes: \(preview.totalDeletes)", systemImage: "trash.fill")
                    .foregroundStyle(preview.totalDeletes > 0 ? AppColors.destructive : .secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }

    private var entityBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Entity")
                .font(.headline)
            let keys = allEntityKeys.sorted()
            if keys.isEmpty {
                Text("No changes detected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 12) {
                        Text(key)
                            .font(.subheadline)
                            .frame(width: 160, alignment: .leading)
                        let ins = preview.entityInserts[key] ?? 0
                        let sk = preview.entitySkips[key] ?? 0
                        let del = preview.entityDeletes[key] ?? 0
                        if ins > 0 { chip(text: "+\(ins)", color: .green, system: "plus") }
                        if sk > 0 { chip(text: "skip \(sk)", color: .secondary, system: "arrow.uturn.left") }
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
                        ForEach(preview.warnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(w)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.yellow.opacity(UIConstants.OpacityConstants.subtle))
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

    private var allEntityKeys: Set<String> {
        var set = Set<String>()
        for k in preview.entityInserts.keys { set.insert(k) }
        for k in preview.entitySkips.keys { set.insert(k) }
        for k in preview.entityDeletes.keys { set.insert(k) }
        return set
    }

    private func chip(text: String, color: Color, system: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(UIConstants.OpacityConstants.medium))
        )
        .foregroundStyle(color)
    }
}

#Preview("Restore Preview") {
    let preview = RestorePreview(
        mode: "merge",
        entityInserts: ["CDStudent": 3, "CDLesson": 1, "LegacyPresentation": 4],
        entitySkips: ["CDStudent": 2, "CDLesson": 0, "LegacyPresentation": 1],
        entityDeletes: ["CDStudent": 0, "CDLesson": 0, "LegacyPresentation": 0],
        totalInserts: 8,
        totalDeletes: 0,
        warnings: ["1 LegacyPresentation records reference missing Lessons and will be skipped."]
    )
    return RestorePreviewView(preview: preview, onCancel: {}, onConfirm: {})
}
