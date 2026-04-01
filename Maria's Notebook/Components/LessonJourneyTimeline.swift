import SwiftUI
import CoreData

/// A visual timeline component showing the journey from lesson to presentations to work to practice sessions
struct LessonJourneyTimeline: View {
    let lesson: CDLesson
    let viewContext: NSManagedObjectContext
    
    @State private var presentations: [CDLessonAssignment] = []
    @State private var allWork: [CDWorkModel] = []
    @State private var allSessions: [CDPracticeSession] = []
    @State private var isLoaded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoaded {
                if presentations.isEmpty {
                    emptyState
                } else {
                    timelineContent
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .task {
            await loadData()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            
            Text("No presentations yet")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.secondary)
            
            Text("This lesson hasn't been presented to any students")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var timelineContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(presentations) { presentation in
                    presentationNode(presentation)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    @ViewBuilder
    private func presentationNode(_ presentation: CDLessonAssignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            presentationCard(presentation)

            let work = allWork.filter { $0.presentationID == presentation.id?.uuidString }
            if !work.isEmpty {
                connectorLine()
                workSection(work)

                let sessions = allSessions.filter { session in
                    work.contains { w in session.workItemIDsArray.contains(w.id?.uuidString ?? "") }
                }
                if !sessions.isEmpty {
                    connectorLine()
                    practiceSection(sessions)
                }
            }
        }
    }

    @ViewBuilder
    private func presentationCard(_ presentation: CDLessonAssignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: presentation.isPresented ? "checkmark.circle.fill" : "calendar")
                    .foregroundStyle(presentation.isPresented ? .green : .blue)
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.isPresented ? "Presented" : presentation.isScheduled ? "Scheduled" : "Draft")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.primary)

                    if let date = presentation.presentedAt ?? presentation.scheduledFor {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let students = presentation.fetchStudents(from: viewContext)
            if !students.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(students.count) \(students.count == 1 ? "Student" : "Students")")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)

                    ForEach(students.prefix(3)) { student in
                        Text("• \(StudentFormatter.displayName(for: student))")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }

                    if students.count > 3 {
                        Text("+ \(students.count - 3) more")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func workSection(_ work: [CDWorkModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("Work (\(work.count))")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
            }

            ForEach(work.prefix(3)) { workItem in
                workItemChip(workItem)
            }

            if work.count > 3 {
                Text("+ \(work.count - 3) more")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(UIConstants.OpacityConstants.hint))
        )
    }

    @ViewBuilder
    private func practiceSection(_ sessions: [CDPracticeSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
                Text("Practice (\(sessions.count))")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
            }

            ForEach(sessions.prefix(3)) { session in
                practiceSessionChip(session)
            }

            if sessions.count > 3 {
                Text("+ \(sessions.count - 3) more")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(UIConstants.OpacityConstants.hint))
        )
    }
    
    @ViewBuilder
    private func connectorLine() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(UIConstants.OpacityConstants.moderate))
            .frame(width: 2, height: 20)
            .padding(.leading, 8)
    }
    
    @ViewBuilder
    private func workItemChip(_ work: CDWorkModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(work.status.color)
                .frame(width: 6, height: 6)
            
            Text(work.title)
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        )
    }
    
    @ViewBuilder
    private func practiceSessionChip(_ session: CDPracticeSession) -> some View {
        HStack(spacing: 6) {
            Image(systemName: session.isGroupSession ? "person.2" : "person")
                .font(.system(size: 10))
                .foregroundStyle(.purple)
            
            Text((session.date ?? Date()).formatted(date: .abbreviated, time: .omitted))
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.purple.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
    
    private func loadData() async {
        presentations = lesson.fetchAllPresentations(from: viewContext)
            .sorted {
                ($0.presentedAt ?? $0.scheduledFor ?? Date.distantPast)
                    > ($1.presentedAt ?? $1.scheduledFor ?? Date.distantPast)
            }
        
        allWork = lesson.fetchAllWork(from: viewContext)
        allSessions = lesson.fetchAllPracticeSessions(from: viewContext)
        
        await MainActor.run {
            isLoaded = true
        }
    }
}

// MARK: - Preview

#Preview("CDLesson Journey Timeline") {
    let stack = CoreDataStack.preview
    let context = stack.viewContext
    let lesson = CDLesson(context: context)
    let _ = { lesson.name = "Long Division"; lesson.subject = "Math"; lesson.group = "Operations" }()

    return ScrollView {
        VStack(spacing: 20) {
            Text("CDLesson Journey")
                .font(AppTheme.ScaledFont.titleLarge)

            LessonJourneyTimeline(lesson: lesson, viewContext: context)
                .frame(height: 400)
        }
        .padding()
    }
    .previewEnvironment(using: stack)
}
