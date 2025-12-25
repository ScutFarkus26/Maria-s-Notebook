import SwiftUI

struct DebugToolsView: View {
    @Binding var showDannyResetConfirm: Bool
    let onScanAndQueue: () -> Void
    let onConsolidate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Danger Zone
            SettingsGroup(title: "Danger Zone", systemImage: "exclamationmark.triangle.fill") {
                Button(role: .destructive) {
                    showDannyResetConfirm = true
                } label: {
                    Label("Delete Lesson & Work History for Danny + Lil Dan D", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Smart Planning (Backfill / Catch Up)
            SettingsGroup(title: "Smart Planning", systemImage: "lightbulb.max") {
                HStack(alignment: .top, spacing: 16) {
                    // 1. Scan & Queue
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            onScanAndQueue()
                        } label: {
                            Label("Scan & Queue 'On Deck' Lessons", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)

                        Text("Scans incomplete work and queues the next lesson. Automatically groups students needing the same lesson.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // 2. Consolidate
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            onConsolidate()
                        } label: {
                            Label("Consolidate 'On Deck' Items", systemImage: "square.on.square.dashed")
                        }
                        .buttonStyle(.bordered)

                        Text("Merges separate cards for the same lesson into one group card in the Inbox.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

