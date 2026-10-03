// TechnicalDetailsDisclosure.swift
// Where raw technical text goes when it's worth keeping on screen: folded
// away under "Details", below the plain-English message, selectable so it
// can be copied into a bug report. The message itself never carries it.

import SwiftUI

struct TechnicalDetailsDisclosure: View {
    let details: String
    @State private var isExpanded = false

    var body: some View {
        if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DisclosureGroup("Details", isExpanded: $isExpanded) {
                Text(details)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
    }
}

#Preview {
    TechnicalDetailsDisclosurePreview()
}

private struct TechnicalDetailsDisclosurePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The classroom share can't send changes to iCloud right now.")
            TechnicalDetailsDisclosure(details: "Classroom share export failed (CKError 12)")
        }
        .padding()
    }
}
