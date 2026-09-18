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
                afterLayout { analyzeScope(.today, mode: .digest) }
            } label: {
                Label("Today", systemImage: "calendar")
            }

            // MARK: Specific Day
            Button {
                afterLayout { showingAIScopeSheet = true }
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
                            afterLayout { analyzeScope(.context(ctx), mode: .digest) }
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
                    afterLayout { analyzeScope(.selectedNotes, mode: .digest) }
                } label: {
                    Label("Selected Notes (\(selectedItemIDs.count))", systemImage: "checkmark.circle")
                }
            }

            Divider()

            // MARK: Summary mode toggle
            Menu {
                Button {
                    afterLayout { startStreamingSummary(mode: .digest) }
                } label: {
                    Label("Key Points", systemImage: "list.bullet")
                }
                Button {
                    afterLayout { startStreamingSummary(mode: .narrative) }
                } label: {
                    Label("Narrative", systemImage: "text.justify")
                }
            } label: {
                Label("Reflect on All Visible", systemImage: "sparkles.rectangle.stack")
            }
        } label: {
            // One symbol, always. "sparkles" and "sparkles.rectangle.stack"
            // are different widths, so letting `isSummarizing` choose between
            // them makes this item's size track state a toolbar reads — and a
            // size that changes while AppKit is measuring the bar is exactly
            // what NSToolbarItemViewer's min/max assertion kills the window
            // over. The menu is disabled for the duration and the summary
            // sheet is on screen throughout, so the swap said it twice anyway.
            Label("Reflect", systemImage: "sparkles")
        }
    }

    /// Runs a Reflect action a turn after the click that asked for it.
    ///
    /// Every action in this menu writes state the Reflect item reads —
    /// `isSummarizing`, or a sheet flag whose presentation re-tiles the bar.
    /// Written while AppKit is inside the toolbar's layout pass, that poisons
    /// the item's measured size to NaN and takes the window down with an
    /// assertion. One turn's delay puts the write after the pass. Same bounce
    /// the album toolbar needed, for the same reason.
    func afterLayout(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }

    // MARK: - On-device, evidence-linked reflection

    func startStreamingSummary(items overrideItems: [UnifiedObservationItem]? = nil, mode: SummaryMode = .digest) {
        guard !isSummarizing else { return }
        guard SystemLanguageModel.default.isAvailable else {
            showingSummarySheet = true
            summaryErrorMessage = "Apple Intelligence is not available on this device right now. "
                + "Your records were not sent anywhere else."
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
            let start = AppCalendar.shared.startOfDay(for: earliest)
            let end = AppCalendar.shared.date(byAdding: .day, value: 1, to: AppCalendar.shared.startOfDay(for: latest))
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
            await runSummary(sourceItems: sourceItems, mode: mode, session: session)
            isSummarizing = false
            summaryTask = nil
        }
    }

    /// Trims the source packets until the prompt fits the on-device budget,
    /// then asks the session for a digest or narrative and stores the result.
    private func runSummary(
        sourceItems: [UnifiedObservationItem],
        mode: SummaryMode,
        session: LanguageModelSession
    ) async {
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
                summaryErrorMessage = "These records do not fit in an on-device reflection. "
                    + "Select fewer observations and try again."
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
            summaryErrorMessage = "The on-device reflection could not be completed. "
                + "Your records were not sent to a cloud model."
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
    func analyzeScope(_ scope: AIAnalysisScope, mode: SummaryMode) {
        let calendar = AppCalendar.shared
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
#endif
