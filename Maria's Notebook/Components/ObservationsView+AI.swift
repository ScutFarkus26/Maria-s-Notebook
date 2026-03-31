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
                Label("Summarize All Visible", systemImage: "sparkles.rectangle.stack")
            }
        } label: {
            Label("AI", systemImage: isSummarizing ? "sparkles.rectangle.stack" : "sparkles")
        }
    }

    // MARK: - Streaming Summary

    @MainActor
    func startStreamingSummary(bodies overrideBodies: [String]? = nil, mode: SummaryMode = .digest) {
        guard !isSummarizing else { return }
        guard SystemLanguageModel.default.isAvailable else { return }
        let sourceBodies: [String]
        if let overrideBodies, !overrideBodies.isEmpty {
            sourceBodies = overrideBodies
        } else {
            sourceBodies = filteredItems.prefix(50).map { "- \($0.body)" }
        }
        guard !sourceBodies.isEmpty else { return }
        let joined = ObservationsHelpers.formatBodiesForSummary(sourceBodies, mode: mode)

        showingSummarySheet = true
        isSummarizing = true
        summaryMode = mode
        summaryPartialDigest = nil
        summaryPartialNarrative = nil

        let instructions = ObservationsHelpers.buildSummaryInstructions()
        let session = LanguageModelSession(instructions: instructions)
        summaryTask?.cancel()
        summaryTask = Task { @MainActor in
            do {
                switch mode {
                case .digest:
                    let stream = session.streamResponse(
                        to: "Summarize the following notes as key points, follow-ups, and sentiment:\n\(joined)",
                        generating: NotesDigest.self
                    )
                    for try await partial in stream {
                        summaryPartialDigest = partial.content
                    }
                case .narrative:
                    let stream = session.streamResponse(
                        to: "Write a single concise narrative paragraph summarizing these observations:\n\(joined)",
                        generating: NotesNarrative.self
                    )
                    for try await partial in stream {
                        summaryPartialNarrative = partial.content
                    }
                }
            } catch {
                Logger.ai.error("[\(#function)] Observations summary failed: \(error)")
            }
            isSummarizing = false
            summaryTask = nil
        }
    }

    func summarizeSelected(as mode: SummaryMode) {
        let bodies = filteredItems.filter { selectedItemIDs.contains($0.id) }.map(\.body)
        startStreamingSummary(bodies: bodies, mode: mode)
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
        let bodies: [String]

        switch scope {
        case .today:
            let todayStart = calendar.startOfDay(for: Date())
            bodies = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == todayStart }
                .map { "- \($0.body)" }

        case .specificDay(let date):
            let dayStart = calendar.startOfDay(for: date)
            bodies = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .map { "- \($0.body)" }

        case .context(let ctx):
            bodies = filteredItems
                .filter { $0.contextText == ctx }
                .map { "- \($0.body)" }

        case .selectedNotes:
            bodies = filteredItems
                .filter { selectedItemIDs.contains($0.id) }
                .map { "- \($0.body)" }
        }

        guard !bodies.isEmpty else { return }
        startStreamingSummary(bodies: bodies, mode: mode)
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
        let partialDigest: NotesDigest.PartiallyGenerated?
        let partialNarrative: NotesNarrative.PartiallyGenerated?
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
                .navigationTitle("Summary")
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
                Text("Summary")
                    .font(AppTheme.ScaledFont.titleMedium)
                Spacer()
                Button(isSummarizing ? "Stop" : "Close") { onCancel() }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch mode {
            case .digest:
                if partialDigest == nil {
                    ProgressView("Generating\u{2026}")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let points = partialDigest?.keyPoints, !points.isEmpty {
                            Text("Key Points").font(.headline)
                            ForEach(points, id: \.self) { p in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill").font(.system(size: 6))
                                    Text(p)
                                }
                            }
                        }
                        if let actions = partialDigest?.followUps, !actions.isEmpty {
                            Divider().padding(.vertical, 8)
                            Text("Follow Ups").font(.headline)
                            ForEach(actions, id: \.self) { a in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle").foregroundStyle(AppColors.success)
                                    Text(a)
                                }
                            }
                        }
                        if let sentiment = partialDigest?.sentiment, !sentiment.isEmpty {
                            Divider().padding(.vertical, 8)
                            HStack {
                                Image(systemName: "face.smiling")
                                Text("Sentiment: \(sentiment)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            case .narrative:
                if partialNarrative == nil {
                    ProgressView("Generating\u{2026}")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let text = partialNarrative?.narrative, !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
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
