// ObservationsView+AI.swift
// AI analysis features for ObservationsView

import OSLog
import SwiftUI
import CoreData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

extension ObservationsView {
    // MARK: - AI Menu

    @available(macOS 26.0, *)
    var aiMenu: some View {
        Menu {
            // MARK: Today
            Button {
                analyzeScope(.today, mode: .digest)
            } label: {
                Label("Today", systemImage: "calendar")
            }

            // MARK: Specific Day
            Button {
                showingAIScopeSheet = true
            } label: {
                Label("Pick a Day\u{2026}", systemImage: "calendar.badge.clock")
            }

            // MARK: By Context / Period
            let contexts = uniqueContexts
            if !contexts.isEmpty {
                Divider()
                Menu {
                    ForEach(contexts, id: \.self) { ctx in
                        Button {
                            analyzeScope(.context(ctx), mode: .digest)
                        } label: {
                            Text(ctx)
                        }
                    }
                } label: {
                    Label("By Context", systemImage: "tray.2")
                }
            }

            // MARK: Selected Notes
            if isSelecting && !selectedItemIDs.isEmpty {
                Divider()
                Button {
                    analyzeScope(.selectedNotes, mode: .digest)
                } label: {
                    Label("Selected Notes (\(selectedItemIDs.count))", systemImage: "checkmark.circle")
                }
            }

            Divider()

            // MARK: Summary mode toggle
            Menu {
                Button {
                    startStreamingSummary(mode: .digest)
                } label: {
                    Label("Key Points", systemImage: "list.bullet")
                }
                Button {
                    startStreamingSummary(mode: .narrative)
                } label: {
                    Label("Narrative", systemImage: "text.justify")
                }
            } label: {
                Label("Reflect on All Visible", systemImage: "sparkles.rectangle.stack")
            }
        } label: {
            Label("Reflect", systemImage: isSummarizing ? "sparkles.rectangle.stack" : "sparkles")
        }
    }

    // MARK: - On-device, evidence-linked reflection

    @MainActor
    func startStreamingSummary(items overrideItems: [UnifiedObservationItem]? = nil, mode: SummaryMode = .digest) {
        guard !isSummarizing else { return }
        guard SystemLanguageModel.default.isAvailable else {
            showingSummarySheet = true
            summaryErrorMessage = "Apple Intelligence is not available on this device right now. Your records were not sent anywhere else."
            return
        }

        let sourceItems = overrideItems?.isEmpty == false ? overrideItems! : Array(filteredItems)
        guard !sourceItems.isEmpty else { return }

        showingSummarySheet = true
        isSummarizing = true
        summaryMode = mode
        summaryDigest = nil
        summaryNarrative = nil
        summaryNarrativeDraft = ""
        summarySources = [:]
        let dates = sourceItems.map(\.date)
        if let earliest = dates.min(), let latest = dates.max() {
            let start = Calendar.current.startOfDay(for: earliest)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: latest))
                ?? latest
            summaryMissingEvidence = PresentationObservationCoverageService.missingObservationReferences(
                in: viewContext,
                from: start,
                through: end,
                studentIDs: Set(sourceItems.flatMap(\.studentIDs))
            )
        } else {
            summaryMissingEvidence = []
        }
        summaryErrorMessage = nil

        let instructions = ObservationsHelpers.buildSummaryInstructions()
        let session = LanguageModelSession(instructions: instructions)
        summaryTask?.cancel()
        summaryTask = Task { @MainActor in
            do {
                var packets = ObservationReflectionService.sourcePackets(from: sourceItems)
                var prompt = ObservationReflectionService.prompt(from: packets, narrative: mode == .narrative)
                let budget = TokenBudget()
                while packets.count > 1,
                      !(await budget.fits(prompt: prompt, reserving: TokenBudget.draftReply)) {
                    packets.removeLast()
                    prompt = ObservationReflectionService.prompt(from: packets, narrative: mode == .narrative)
                }

                guard !packets.isEmpty,
                      await budget.fits(prompt: prompt, reserving: TokenBudget.draftReply) else {
                    summaryErrorMessage = "These records do not fit in an on-device reflection. Select fewer observations and try again."
                    isSummarizing = false
                    summaryTask = nil
                    return
                }

                summarySources = ObservationReflectionService.referenceMap(from: packets)
                switch mode {
                case .digest:
                    let response = try await session.respond(to: prompt, generating: NotesDigest.self)
                    summaryDigest = ObservationReflectionService.validate(response.content, against: packets)
                case .narrative:
                    let response = try await session.respond(to: prompt, generating: NotesNarrative.self)
                    summaryNarrative = response.content
                    summaryNarrativeDraft = response.content.narrative
                }
            } catch {
                Logger.ai.error("[\(#function)] Observations reflection failed: \(error)")
                summaryErrorMessage = "The on-device reflection could not be completed. Your records were not sent to a cloud model."
            }
            isSummarizing = false
            summaryTask = nil
        }
    }

    // MARK: - AI Scope Analysis

    /// Unique context strings from the current filtered items, for the "By Context" menu.
    var uniqueContexts: [String] {
        let all = filteredItems.compactMap(\.contextText)
        // Deduplicate while preserving order
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    /// Runs the AI summary for a given scope.
    @MainActor
    func analyzeScope(_ scope: AIAnalysisScope, mode: SummaryMode) {
        let calendar = Calendar.current
        let items: [UnifiedObservationItem]

        switch scope {
        case .today:
            let todayStart = calendar.startOfDay(for: Date())
            items = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == todayStart }

        case .specificDay(let date):
            let dayStart = calendar.startOfDay(for: date)
            items = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == dayStart }

        case .context(let ctx):
            items = filteredItems
                .filter { $0.contextText == ctx }

        case .selectedNotes:
            items = filteredItems
                .filter { selectedItemIDs.contains($0.id) }
        }

        guard !items.isEmpty else { return }
        startStreamingSummary(items: items, mode: mode)
    }
}

// MARK: - Day Picker Sheet

extension ObservationsView {
    struct AIDayPickerSheet: View {
        @Binding var date: Date
        let onConfirm: (Date) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            #if os(macOS)
            VStack(spacing: 16) {
                Text("Pick a Day")
                    .font(AppTheme.ScaledFont.titleSmall)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Analyze") { onConfirm(date) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 340)
            .presentationSizingFitted()
            #else
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Button("Analyze") { onConfirm(date) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .navigationTitle("Pick a Day")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

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
                                            "\(reference.title) — \(reference.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "Unknown date")",
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
