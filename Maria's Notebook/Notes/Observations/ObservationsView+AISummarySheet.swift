// ObservationsView+AISummarySheet.swift
// Sheet that presents the on-device, evidence-linked reflection.

import SwiftUI

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - Summary Sheet

extension ObservationsView {
    struct ObservationsSummarySheet: View {
        let mode: SummaryMode
        @Binding var isSummarizing: Bool
        let digest: NotesDigest?
        let narrative: NotesNarrative?
        @Binding var narrativeDraft: String
        let sources: [String: EvidenceReference]
        let missingEvidence: [EvidenceReference]
        let errorMessage: String?
        let onOpenSource: (EvidenceReference) -> Void
        let onCancel: () -> Void

        var body: some View {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                header
                content
                footer
            }
            .padding(20)
            .frame(minWidth: 420, minHeight: 360)
            .presentationSizingFitted()
            #else
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
                .navigationTitle(mode == .digest ? "Observation Reflection" : "Narrative Draft")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isSummarizing ? "Stop" : "Close") { onCancel() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }

        @ViewBuilder
        private var header: some View {
            HStack {
                Text(mode == .digest ? "Observation Reflection" : "Narrative Draft")
                    .font(AppTheme.ScaledFont.titleMedium)
                Label("On Device", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isSummarizing ? "Stop" : "Close") { onCancel() }
            }
        }

        @ViewBuilder
        private var content: some View {
            if let errorMessage {
                ContentUnavailableView(
                    "Reflection Unavailable",
                    systemImage: "sparkles",
                    description: Text(errorMessage)
                )
            } else {
                switch mode {
                case .digest:
                    if digest == nil {
                        ProgressView("Reviewing records\u{2026}")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if !missingEvidence.isEmpty {
                                    Text("Presentations Without a Linked Observation")
                                        .font(.headline)
                                    Text("This is a record check, not an AI conclusion.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(missingEvidence) { reference in
                                        Label(
                                            "\(reference.title) — \(missingEvidenceDate(reference))",
                                            systemImage: "exclamationmark.bubble"
                                        )
                                    }
                                    Divider().padding(.vertical, 4)
                                }
                                findingsSection(
                                    "Factual Observations",
                                    findings: digest?.factualObservations ?? [],
                                    icon: "text.quote"
                                )
                                findingsSection(
                                    "Patterns to Review",
                                    findings: digest?.repeatedPatterns ?? [],
                                    icon: "point.3.connected.trianglepath.dotted"
                                )
                                findingsSection(
                                    "Questions to Observe Next",
                                    findings: digest?.questionsToObserveNext ?? [],
                                    icon: "eye"
                                )
                            }
                        }
                    }
                case .narrative:
                    if narrative == nil {
                        ProgressView("Generating\u{2026}")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Editable AI draft — verify it against the records below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !narrativeDraft.isEmpty {
                                    TextEditor(text: $narrativeDraft)
                                        .font(.body)
                                        .frame(minHeight: 160)
                                        .padding(8)
                                        .background(
                                            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .accessibilityLabel("Editable narrative draft")
                                }
                                Text("Records Reviewed")
                                    .font(.headline)
                                sourceButtons(keys: sources.keys.sorted())
                            }
                        }
                    }
                }
            }
        }

        private func missingEvidenceDate(_ reference: EvidenceReference) -> String {
            reference.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "Unknown date"
        }

        @ViewBuilder
        private func findingsSection(
            _ title: String,
            findings: [GroundedObservationFinding],
            icon: String
        ) -> some View {
            if !findings.isEmpty {
                Text(title).font(.headline)
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(finding.text, systemImage: icon)
                        sourceButtons(keys: finding.sourceKeys)
                    }
                }
                Divider().padding(.vertical, 4)
            }
        }

        private func sourceButtons(keys: [String]) -> some View {
            FlowLayout(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    if let reference = sources[key] {
                        Button {
                            onOpenSource(reference)
                        } label: {
                            Label(key, systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .help("\(reference.title): \(reference.excerpt)")
                    }
                }
            }
        }

        @ViewBuilder
        private var footer: some View {
            HStack {
                Spacer()
                Button(isSummarizing ? "Stop" : "Close") { onCancel() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
#endif
