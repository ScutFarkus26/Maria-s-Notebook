//
//  StudentInsightsView+Sections.swift
//  Maria's Notebook
//
//  Insight section view builders for StudentInsightsView
//

import SwiftUI
import SwiftData

extension StudentInsightsView {

    // MARK: - Header Section

    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Development Insights")
                .font(.title2)
                .fontWeight(.bold)

            Text("AI-powered analysis of \(student.fullName)'s recent progress")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Analysis Period:")
                    .font(.subheadline)

                Picker("Days", selection: $selectedLookbackDays) {
                    ForEach(lookbackOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Latest Insights Card

    // swiftlint:disable:next function_body_length
    func latestInsightsCard(_ snapshot: DevelopmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Analysis")
                        .font(.headline)
                    Text(snapshot.generatedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !snapshot.isReviewed {
                    Label("New", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
                        .cornerRadius(8)
                }
            }

            Divider()

            // Overall Progress
            VStack(alignment: .leading, spacing: 8) {
                Label("Overall Progress", systemImage: SFSymbol.Chart.chartLine)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(snapshot.overallProgress)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Divider()

            // Metrics
            metricsGrid(snapshot)

            Divider()

            // Key Strengths
            if !snapshot.keyStrengths.isEmpty {
                insightSection(
                    title: "Key Strengths",
                    icon: "star.fill",
                    color: .green,
                    items: snapshot.keyStrengths
                )
            }

            // Areas for Growth
            if !snapshot.areasForGrowth.isEmpty {
                insightSection(
                    title: "Areas for Growth",
                    icon: "arrow.up.circle.fill",
                    color: .blue,
                    items: snapshot.areasForGrowth
                )
            }

            // Recommendations
            if !snapshot.recommendedNextLessons.isEmpty {
                insightSection(
                    title: "Recommended Next Steps",
                    icon: "lightbulb.fill",
                    color: .orange,
                    items: snapshot.recommendedNextLessons
                )
            }

            // Interventions (if any)
            if !snapshot.interventionSuggestions.isEmpty {
                insightSection(
                    title: "Intervention Suggestions",
                    icon: "bandage.fill",
                    color: .red,
                    items: snapshot.interventionSuggestions
                )
            }

            Divider()

            // Actions
            HStack {
                Button(action: { markAsReviewed(snapshot) }, label: {
                    Label(snapshot.isReviewed ? "Reviewed" : "Mark Reviewed", systemImage: "checkmark.circle")
                })
                .buttonStyle(.bordered)
                .disabled(snapshot.isReviewed)

                Spacer()

                Button(action: { generateParentSummary(snapshot) }, label: {
                    Label("Share with Parents", systemImage: "square.and.arrow.up")
                })
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Metrics Grid

    func metricsGrid(_ snapshot: DevelopmentSnapshot) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            metricCard(
                title: "Notes",
                value: "\(snapshot.totalNotesAnalyzed)",
                icon: "note.text"
            )

            metricCard(
                title: "Sessions",
                value: "\(snapshot.practiceSessionsAnalyzed)",
                icon: "figure.walk"
            )

            metricCard(
                title: "Completions",
                value: "\(snapshot.workCompletionsAnalyzed)",
                icon: "checkmark.circle"
            )

            if let quality = snapshot.averagePracticeQuality {
                metricCard(
                    title: "Quality",
                    value: quality.formatAsScore(),
                    icon: "star.fill"
                )
            }

            if let independence = snapshot.independenceLevel {
                metricCard(
                    title: "Independence",
                    value: independence.formatAsScore(),
                    icon: "person.fill.checkmark"
                )
            }
        }
    }

    func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlColor))
        #endif
        .cornerRadius(8)
    }

    // MARK: - Insight Section

    func insightSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color.opacity(UIConstants.OpacityConstants.semi))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(item)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Generate Button

    var generateButton: some View {
        Button(action: generateNewAnalysis) {
            if isGenerating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Label("Generate New Analysis", systemImage: SFSymbol.Tool.wand)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isGenerating)
    }

    // MARK: - Error Card

    func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Error", systemImage: SFSymbol.Status.exclamationmarkTriangleFill)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.destructive)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)

            // Show settings button if API key is missing
            if message.contains("API key") {
                Button(action: { showingAPIKeySettings = true }, label: {
                    Label("Configure API Key", systemImage: SFSymbol.Settings.gear)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                })
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.red.opacity(UIConstants.OpacityConstants.light))
        .cornerRadius(12)
    }

    // MARK: - History Section

    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous Analyses")
                .font(.headline)

            ForEach(Array(snapshots.dropFirst()), id: \.id) { snapshot in
                Button(action: { /* Navigate to detail view */ }, label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.generatedAt, style: .date)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(snapshot.lookbackDays) days \u{2022} \(snapshot.totalNotesAnalyzed) notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(.secondarySystemBackground))
                    #else
                    .background(Color(NSColor.controlColor))
                    #endif
                    .cornerRadius(8)
                })
                .buttonStyle(.plain)
            }
        }
    }
}
