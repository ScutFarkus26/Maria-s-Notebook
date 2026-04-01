//
//  StudentInsightsView.swift
//  Maria's Notebook
//
//  UI for displaying MCP-powered student development insights
//

import SwiftUI
import CoreData
import OSLog

/// View displaying AI-generated student development insights
struct StudentInsightsView: View {
    private static let logger = Logger.students
    @Environment(\.dependencies) var dependencies
    @Environment(\.managedObjectContext) var viewContext

    let student: CDStudent

    @State var snapshots: [CDDevelopmentSnapshotEntity] = []
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
        .navigationTitle("CDStudent Insights")
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
        let studentIDString = student.id?.uuidString ?? ""
        let descriptor: NSFetchRequest<CDDevelopmentSnapshotEntity> = NSFetchRequest(entityName: "DevelopmentSnapshot")
        descriptor.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        descriptor.sortDescriptors = [NSSortDescriptor(key: "generatedAt", ascending: false)]

        do {
            snapshots = try viewContext.fetch(descriptor)
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
                errorMessage = "Please configure your Anthropic API key in Settings"
                    + " \u{2192} AI Features to use Development Insights."
                isGenerating = false
                return
            }

            do {
                let snapshot = try await dependencies.studentAnalysisService.analyzeStudent(
                    student,
                    lookbackDays: selectedLookbackDays
                )

                viewContext.insert(snapshot)
                try viewContext.save()

                await loadSnapshots()
            } catch {
                errorMessage = "Failed to generate analysis: \(error.localizedDescription)"
            }

            isGenerating = false
        }
    }

    func markAsReviewed(_ snapshot: CDDevelopmentSnapshotEntity) {
        snapshot.isReviewed = true
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save: \(error)")
        }
    }

    func generateParentSummary(_ snapshot: CDDevelopmentSnapshotEntity) {
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
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let student = CDStudent(context: ctx)
    student.firstName = "Emma"
    student.lastName = "Johnson"
    student.birthday = Calendar.current.date(byAdding: .year, value: -4, to: Date())!
    student.level = .lower

    let snapshot = CDDevelopmentSnapshotEntity(context: ctx)
    snapshot.studentID = student.id?.uuidString ?? ""
    snapshot.generatedAt = Date()
    snapshot.lookbackDays = 30
    snapshot.overallProgress = "Emma shows steady progress across academic and social domains." +
        " Notable growth in independence and peer collaboration."
    snapshot.keyStrengths = ["Strong focus during practice", "Helps peers frequently", "Growing independence"]
    snapshot.areasForGrowth = ["Building confidence with new materials", "Managing frustration"]
    snapshot.developmentalMilestones = ["Consistent 3-period retention", "Age-appropriate fine motor control"]
    snapshot.recommendedNextLessons = ["Complex math materials", "Extended practical life"]
    snapshot.totalNotesAnalyzed = 12
    snapshot.practiceSessionsAnalyzed = 8
    snapshot.workCompletionsAnalyzed = 5
    snapshot.averagePracticeQuality = 4.2
    snapshot.independenceLevel = 3.8

    return NavigationStack {
        StudentInsightsView(student: student)
            .previewEnvironment(using: stack)
            .environment(\.dependencies, AppDependencies(coreDataStack: stack))
    }
}
