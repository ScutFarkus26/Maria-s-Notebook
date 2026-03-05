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
    @Environment(\.dependencies) var dependencies
    @Environment(\.modelContext) var modelContext

    let student: Student

    @State var snapshots: [DevelopmentSnapshot] = []
    @State var isGenerating = false
    @State var errorMessage: String?
    @State var selectedLookbackDays = 30
    @State var showingParentSummary = false
    @State var parentSummary = ""
    @State var showingAPIKeySettings = false

    let lookbackOptions = [7, 14, 30, 60, 90]

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

    // MARK: - Actions

    func loadSnapshots() async {
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

    func generateNewAnalysis() {
        Task {
            isGenerating = true
            errorMessage = nil

            // Check if API key is configured
            if !AnthropicAPIClient.hasAPIKey() {
                errorMessage = "Please configure your Anthropic API key in Settings \u{2192} AI Features to use Development Insights."
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

    func markAsReviewed(_ snapshot: DevelopmentSnapshot) {
        snapshot.isReviewed = true
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save: \(error)")
        }
    }

    func generateParentSummary(_ snapshot: DevelopmentSnapshot) {
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
