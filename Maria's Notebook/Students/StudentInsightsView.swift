//
//  StudentInsightsView.swift
//  Maria's Notebook
//
//  UI for displaying MCP-powered student development insights
//

import SwiftUI
import SwiftData
import OSLog

/// View displaying AI-generated student development insights
struct StudentInsightsView: View {
    private static let logger = Logger.students
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    
    let student: Student
    
    @State private var snapshots: [DevelopmentSnapshot] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var selectedLookbackDays = 30
    @State private var showingParentSummary = false
    @State private var parentSummary = ""
    @State private var showingAPIKeySettings = false
    
    private let lookbackOptions = [7, 14, 30, 60, 90]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Latest snapshot
                if let latest = snapshots.first {
                    latestInsightsCard(latest)
                }
                
                // Generate new analysis button
                generateButton
                
                // Error display
                if let error = errorMessage {
                    errorCard(error)
                }
                
                // Historical snapshots
                if snapshots.count > 1 {
                    historySection
                }
            }
            .padding()
        }
        .navigationTitle("Student Insights")
        .task {
            await loadSnapshots()
        }
        .sheet(isPresented: $showingParentSummary) {
            ParentSummarySheet(summary: parentSummary, student: student)
        }
        .sheet(isPresented: $showingAPIKeySettings) {
            NavigationStack {
                APIKeySettingsView()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
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
    
    private func latestInsightsCard(_ snapshot: DevelopmentSnapshot) -> some View {
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
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
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
                Button(action: { markAsReviewed(snapshot) }) {
                    Label(snapshot.isReviewed ? "Reviewed" : "Mark Reviewed", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.isReviewed)
                
                Spacer()
                
                Button(action: { generateParentSummary(snapshot) }) {
                    Label("Share with Parents", systemImage: "square.and.arrow.up")
                }
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
    
    private func metricsGrid(_ snapshot: DevelopmentSnapshot) -> some View {
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
    
    private func metricCard(title: String, value: String, icon: String) -> some View {
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
    
    private func insightSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color.opacity(0.3))
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
    
    private var generateButton: some View {
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
    
    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Error", systemImage: SFSymbol.Status.exclamationmarkTriangleFill)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
            
            // Show settings button if API key is missing
            if message.contains("API key") {
                Button(action: { showingAPIKeySettings = true }) {
                    Label("Configure API Key", systemImage: SFSymbol.Settings.gear)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous Analyses")
                .font(.headline)
            
            ForEach(Array(snapshots.dropFirst()), id: \.id) { snapshot in
                Button(action: { /* Navigate to detail view */ }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.generatedAt, style: .date)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(snapshot.lookbackDays) days • \(snapshot.totalNotesAnalyzed) notes")
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
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadSnapshots() async {
        let studentIDString = student.id.uuidString
        let descriptor = FetchDescriptor<DevelopmentSnapshot>(
            predicate: #Predicate<DevelopmentSnapshot> { snapshot in
                snapshot.studentID == studentIDString
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        
        do {
            snapshots = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load snapshots: \(error.localizedDescription)"
        }
    }
    
    private func generateNewAnalysis() {
        Task {
            isGenerating = true
            errorMessage = nil
            
            // Check if API key is configured
            if !AnthropicAPIClient.hasAPIKey() {
                errorMessage = "Please configure your Anthropic API key in Settings → AI Features to use Development Insights."
                isGenerating = false
                return
            }
            
            do {
                let snapshot = try await dependencies.studentAnalysisService.analyzeStudent(
                    student,
                    lookbackDays: selectedLookbackDays
                )
                
                modelContext.insert(snapshot)
                try modelContext.save()
                
                await loadSnapshots()
            } catch {
                errorMessage = "Failed to generate analysis: \(error.localizedDescription)"
            }
            
            isGenerating = false
        }
    }
    
    private func markAsReviewed(_ snapshot: DevelopmentSnapshot) {
        snapshot.isReviewed = true
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save: \(error)")
        }
    }
    
    private func generateParentSummary(_ snapshot: DevelopmentSnapshot) {
        Task {
            do {
                parentSummary = try await dependencies.studentAnalysisService.generateParentSummary(snapshot: snapshot)
                showingParentSummary = true
            } catch {
                errorMessage = "Failed to generate parent summary: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Parent Summary Sheet

struct ParentSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: String
    let student: Student
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Progress Summary for \(student.fullName)")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)
                    
                    Divider()
                    
                    Text("This summary was generated using AI-powered analysis of classroom observations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Parent Summary")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: summary) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    let student = Student(
        firstName: "Emma",
        lastName: "Johnson",
        birthday: Calendar.current.date(byAdding: .year, value: -4, to: Date())!,
        level: .lower
    )
    context.insert(student)
    
    let snapshot = DevelopmentSnapshot(
        studentID: student.id.uuidString,
        generatedAt: Date(),
        lookbackDays: 30,
        overallProgress: "Emma shows steady progress across academic and social domains. Notable growth in independence and peer collaboration.",
        keyStrengths: ["Strong focus during practice", "Helps peers frequently", "Growing independence"],
        areasForGrowth: ["Building confidence with new materials", "Managing frustration"],
        developmentalMilestones: ["Consistent 3-period retention", "Age-appropriate fine motor control"],
        recommendedNextLessons: ["Complex math materials", "Extended practical life"],
        totalNotesAnalyzed: 12,
        practiceSessionsAnalyzed: 8,
        workCompletionsAnalyzed: 5,
        averagePracticeQuality: 4.2,
        independenceLevel: 3.8
    )
    context.insert(snapshot)
    
    return NavigationStack {
        StudentInsightsView(student: student)
            .modelContainer(container)
            .environment(\.dependencies, AppDependencies(modelContext: context))
    }
}
