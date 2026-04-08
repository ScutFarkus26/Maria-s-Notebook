// WorkCycleView.swift
// Root view for the Work Cycle Tracker — timer, student grid, and session management.

import SwiftUI
import CoreData

struct WorkCycleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = WorkCycleViewModel()
    @State private var selectedStudentID: UUID?
    @State private var showingSummary = false

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCycleEntry.createdAt, ascending: false)]
    ) private var allEntries: FetchedResults<CDWorkCycleEntry>

    private var changeToken: Int { allEntries.count }

    var body: some View {
        content
            .navigationTitle("Work Cycle")
            .searchable(text: $viewModel.searchText, prompt: "Search students")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in
                if let session = viewModel.session {
                    viewModel.loadStudents(context: viewContext)
                    _ = session // suppress unused warning
                }
            }
            .sheet(item: $selectedStudentID) { studentID in
                WorkCycleEntrySheet(
                    studentID: studentID,
                    studentName: viewModel.studentCards.first { $0.id == studentID }?.displayName ?? "",
                    onSave: { activity, socialMode, concentration, workItemID in
                        viewModel.addEntry(
                            studentID: studentID,
                            activity: activity,
                            socialMode: socialMode,
                            concentration: concentration,
                            workItemID: workItemID,
                            context: viewContext
                        )
                    }
                )
            }
            .sheet(isPresented: $showingSummary) {
                if let summary = viewModel.cycleSummary {
                    WorkCycleSummaryView(summary: summary)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasActiveSession {
            activeSessionContent
        } else {
            noSessionContent
        }
    }

    // MARK: - Active Session

    private var activeSessionContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Timer display
                timerSection
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Session controls
                sessionControls
                    .padding(.horizontal)

                // Level filter
                levelFilter
                    .padding(.horizontal)

                // Student grid
                studentGrid
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
    }

    private var timerSection: some View {
        VStack(spacing: 4) {
            Text(viewModel.elapsedFormatted)
                .font(.system(size: 48, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(viewModel.session?.isPaused == true ? AppColors.warning : .primary)

            HStack(spacing: 8) {
                Image(systemName: viewModel.session?.status.icon ?? "timer")
                    .font(.caption)
                    .foregroundStyle(viewModel.session?.status.color ?? .secondary)
                Text(viewModel.session?.status.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardStyle()
    }

    private var sessionControls: some View {
        HStack(spacing: 12) {
            if viewModel.session?.isPaused == true {
                Button {
                    viewModel.resumeSession(context: viewContext)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.success)
            } else {
                Button {
                    viewModel.pauseSession(context: viewContext)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                viewModel.endSession(context: viewContext)
                showingSummary = true
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppColors.destructive)
        }
    }

    private var levelFilter: some View {
        Picker("Level", selection: $viewModel.levelFilter) {
            ForEach(LevelFilter.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Student Grid

    private var studentGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 140, maximum: 280), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.filteredCards) { card in
                studentCardView(card)
                    .onTapGesture {
                        selectedStudentID = card.id
                    }
            }
        }
    }

    private func studentCardView(_ card: StudentCycleCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(String(card.firstName.prefix(1)))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        AppColors.color(forLevel: card.level).gradient,
                        in: Circle()
                    )

                Text(card.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if card.entryCount > 0 {
                    Text("\(card.entryCount)")
                        .font(.system(size: 9))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.blue.gradient)
                        )
                }
            }

            if let activity = card.currentActivity {
                Text(activity)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let concentration = card.concentration {
                HStack(spacing: 3) {
                    Image(systemName: concentration.icon)
                        .font(.system(size: 8))
                    Text(concentration.displayName)
                        .font(.system(size: 8))
                }
                .foregroundStyle(concentration.color)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(UIConstants.OpacityConstants.subtle), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small, style: .continuous)
                .strokeBorder(
                    card.concentration?.color.opacity(0.3) ?? Color.clear,
                    lineWidth: card.entryCount > 0 ? 1.5 : 0.5
                )
        }
    }

    // MARK: - No Session

    private var noSessionContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Start button
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Start a Work Cycle")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Track what students are working on during the uninterrupted work period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.startNewSession(context: viewContext)
                    } label: {
                        Label("Start Work Cycle", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .padding(.top, 20)

                // Past sessions
                if !viewModel.pastSessions.isEmpty {
                    pastSessionsList
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var pastSessionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.pastSessions, id: \.id) { session in
                    pastSessionRow(session)
                }
            }
        }
    }

    private func pastSessionRow(_ session: CDWorkCycleSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                .font(.caption)
                .foregroundStyle(AppColors.success)

            VStack(alignment: .leading, spacing: 2) {
                if let date = session.date {
                    Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(session.durationFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .cardStyle()
    }
}
