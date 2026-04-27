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
        if visibleKinds.contains(kind) {
            guard visibleKinds.count > 1 else { return }
            visibleKinds.remove(kind)
        } else {
            visibleKinds.insert(kind)
        }
    }
}

#Preview {
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
