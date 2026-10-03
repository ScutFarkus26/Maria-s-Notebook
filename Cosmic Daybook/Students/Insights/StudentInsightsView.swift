//
//  StudentInsightsView.swift
//  Cosmic Daybook
//
//  UI for displaying MCP-powered student development insights
//

import SwiftUI
import CoreData
import OSLog

/// View displaying AI-generated student development insights
struct StudentInsightsView: View {
    static let logger = Logger.students

    @Environment(\.dependencies) var dependencies
    @Environment(\.managedObjectContext) var viewContext

    let student: CDStudent

    @State var snapshots: [CDDevelopmentSnapshotEntity] = []
    @State var isGenerating = false
    @State var errorMessage: String?
    @State var errorTitle = "Couldn't Make Insights"
    @State var selectedLookbackDays = 30
    @State var showingParentSummary = false
    @State var parentSummary = ""

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
            Self.logger.error("Couldn't fetch development snapshots: \(error, privacy: .public)")
            errorTitle = "Couldn't Load Insights"
            errorMessage = "Couldn't load \(student.firstName)'s past insights. Close this screen and open it again."
        }
    }

    func generateNewAnalysis() {
        Task {
            isGenerating = true
            errorMessage = nil

            defer { isGenerating = false }
            errorTitle = "Couldn't Make Insights"

            let snapshot: CDDevelopmentSnapshotEntity
            do {
                snapshot = try await dependencies.studentAnalysisService.analyzeStudent(
                    student,
                    lookbackDays: selectedLookbackDays
                )
            } catch {
                Self.logger.error("Insights analysis failed: \(error, privacy: .public)")
                errorMessage = AppErrorMessages.aiMessage(
                    for: error,
                    fallback: "Couldn't look over \(student.firstName)'s notes and work right now. Try again."
                )
                return
            }

            // A failed save isn't an Apple Intelligence failure, so it says so.
            viewContext.insert(snapshot)
            do {
                try viewContext.save()
            } catch {
                Self.logger.error("Couldn't save the new insights: \(error, privacy: .public)")
                viewContext.delete(snapshot)
                errorMessage = "Couldn't save the new insights. Try again."
                return
            }

            await loadSnapshots()
        }
    }

    func markAsReviewed(_ snapshot: CDDevelopmentSnapshotEntity) {
        snapshot.isReviewed = true
        dependencies.saveCoordinator.save(viewContext, reason: "Mark snapshot reviewed")
    }

    func generateParentSummary(_ snapshot: CDDevelopmentSnapshotEntity) {
        Task {
            do {
                parentSummary = try await dependencies.studentAnalysisService.generateParentSummary(snapshot: snapshot)
                showingParentSummary = true
            } catch {
                Self.logger.error("Parent summary failed: \(error, privacy: .public)")
                errorTitle = "Couldn't Write the Summary"
                errorMessage = AppErrorMessages.aiMessage(
                    for: error,
                    fallback: "Couldn't draft a summary for parents right now. Try again."
                )
            }
        }
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct StudentInsightsViewPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext

        let student = CDStudent(context: ctx)
        student.firstName = "Emma"
        student.lastName = "Johnson"
        student.birthday = AppCalendar.shared.date(byAdding: .year, value: -4, to: Date())!
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
}

#Preview {
    StudentInsightsViewPreview()
}
