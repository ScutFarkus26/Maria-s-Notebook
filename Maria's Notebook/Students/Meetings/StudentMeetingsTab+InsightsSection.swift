// StudentMeetingsTab+InsightsSection.swift
// Meeting insights section with AI-powered analysis

import OSLog
import SwiftUI

extension StudentMeetingsTab {

    var meetingInsightsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                // Header with timeframe picker
                HStack {
                    Label("Meeting Insights", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Picker("Period", selection: $insightsTimeframeDays) {
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                        Text("3 months").tag(90)
                        Text("6 months").tag(180)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                if isGeneratingInsights {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing meetings...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if let insights = meetingInsights {
                    insightsContent(insights)
                } else if let error = insightsError {
                    insightsErrorView(error)
                } else {
                    // Empty/initial state — auto-generation will handle this
                    Text("Insights will appear here after analysis.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Insights Content

    @ViewBuilder
    func insightsContent(_ insights: MeetingInsightsResult) -> some View {
        // Sentiment + Summary
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: insights.sentiment.icon)
                    .foregroundStyle(sentimentColor(insights.sentiment))
                Text(insights.sentiment.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sentimentColor(insights.sentiment))
            }

            Text(insights.progressSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }

        // Progress Trends
        if !insights.progressTrends.isEmpty {
            insightsList(
                title: "Progress",
                icon: "arrow.up.right",
                color: .green,
                items: insights.progressTrends
            )
        }

        // Regression Signals
        if !insights.regressionSignals.isEmpty {
            insightsList(
                title: "Needs Attention",
                icon: "exclamationmark.triangle",
                color: .orange,
                items: insights.regressionSignals
            )
        }

        // Neglected Areas
        if !insights.neglectedAreas.isEmpty {
            insightsList(
                title: "May Need Coverage",
                icon: "eye.slash",
                color: .blue,
                items: insights.neglectedAreas
            )
        }

        // Action Items
        if !insights.actionItems.isEmpty {
            insightsList(
                title: "Suggested Actions",
                icon: "checklist",
                color: .accentColor,
                items: insights.actionItems
            )
        }

        // Footer
        HStack {
            Text("\(insights.analyzedMeetingCount) meetings analyzed (\(insights.timeframeDescription))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                Task { await generateInsights() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.accent)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    func insightsErrorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !AnthropicAPIClient.hasAPIKey() {
                Button {
                    showingAPIKeySettings = true
                } label: {
                    Label("Configure API Key", systemImage: "key")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    Task { await generateInsights() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    func insightsList(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)

                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    func sentimentColor(_ sentiment: MeetingSentiment) -> Color {
        switch sentiment {
        case .confident: .green
        case .progressing: .blue
        case .mixed: .orange
        case .struggling: .red
        case .insufficient: .secondary
        }
    }

    func generateInsights() async {
        guard !isGeneratingInsights else { return }

        isGeneratingInsights = true
        insightsError = nil

        guard let studentID = student.id else {
            insightsError = "Unable to identify student."
            isGeneratingInsights = false
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -insightsTimeframeDays, to: Date()) ?? Date()
        let relevantMeetings = meetingItems.filter { ($0.date ?? .distantPast) >= cutoff }

        guard !relevantMeetings.isEmpty else {
            insightsError = "No meetings found in this timeframe."
            isGeneratingInsights = false
            return
        }

        let studentWorkModels = allWorkModels.filter { $0.studentID == studentID.uuidString }

        do {
            meetingInsights = try await dependencies.meetingInsightsService.analyzeMeetings(
                for: student,
                meetings: relevantMeetings,
                workModels: Array(studentWorkModels),
                lessonAssignments: lessonsSinceLastMeetingForStudent,
                timeframeDays: insightsTimeframeDays
            )
        } catch {
            Self.logger.warning("Meeting insights generation failed: \(error)")
            insightsError = "Unable to generate insights. Please try again."
        }

        isGeneratingInsights = false
    }
}
