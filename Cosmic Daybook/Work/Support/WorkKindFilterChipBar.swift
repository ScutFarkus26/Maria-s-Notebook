// WorkKindFilterChipBar.swift
// Horizontal toggle-chip bar for filtering open work by WorkKind.

import SwiftUI

struct WorkKindFilterChipBar: View {
    @Binding var visibleKinds: Set<WorkKind>

    private var allActive: Bool { visibleKinds.count == WorkKind.allCases.count }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    isActive: allActive,
                    onTap: { visibleKinds = Set(WorkKind.allCases) }
                )

                ForEach(WorkKind.allCases) { kind in
                    FilterChip(
                        label: kind.shortLabel,
                        icon: kind.iconName,
                        isActive: visibleKinds.contains(kind),
                        activeColor: kind.color,
                        onTap: { toggle(kind) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func toggle(_ kind: WorkKind) {
        if allActive {
            visibleKinds = [kind]
            return
        }

        if visibleKinds.contains(kind) {
            guard visibleKinds.count > 1 else { return }
            visibleKinds.remove(kind)
        } else {
            visibleKinds.insert(kind)
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct WorkKindFilterChipBarPreview: View {
    var body: some View {
        struct Wrapper: View {
            @State var kinds: Set<WorkKind> = Set(WorkKind.allCases)
            var body: some View {
                VStack {
                    WorkKindFilterChipBar(visibleKinds: $kinds)
                    Text("Active: \(kinds.map(\.shortLabel).sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        return Wrapper()
    }
}

#Preview {
    WorkKindFilterChipBarPreview()
}
