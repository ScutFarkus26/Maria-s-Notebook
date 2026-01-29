import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

struct MeetingsAgendaView: View {
    @State private var viewModel = MeetingsAgendaViewModel()
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Cache for student lookups
    @Query private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    var body: some View {
        let days = viewModel.days
        return AgendaShellView(
            sidebar: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Meetings")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(width: 280)
            },
            header: {
                VStack(spacing: 0) {
                    AgendaWeekHeaderView(
                        startDate: viewModel.startDate,
                        days: days,
                        onPrev: { withAnimation { viewModel.move(by: -5) } },
                        onNext: { withAnimation { viewModel.move(by: 5) } },
                        onToday: { withAnimation { viewModel.resetToToday() } },
                        actions: { EmptyView() }
                    )
                    AgendaDayStripView(days: days) { day in
                        viewModel.scrollToDay = day
                    }
                }
            },
            content: {
                ScrollViewReader { proxy in
                    AgendaView(
                        days: days,
                        dayID: { day in viewModel.dayID(day) },
                        dayHeader: { day in AgendaDaySectionHeaderView(day: day, isNonSchoolDay: false) },
                        contentForDay: { day in
                            // Fetch meetings for this specific day
                            let dailyMeetings = viewModel.meetings(for: day)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                if dailyMeetings.isEmpty {
                                    Text("No meetings")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(dailyMeetings) { meeting in
                                        MeetingSummaryCard(
                                            meeting: meeting,
                                            student: resolveStudent(id: meeting.studentID)
                                        )
                                    }
                                }
                            }
                        }
                    )
                    .onChange(of: viewModel.scrollToDay) { _, new in
                        if let d = new { withAnimation { proxy.scrollTo(viewModel.dayID(d), anchor: .top) } }
                    }
                }
            }
        )
        .onAppear {
            viewModel.modelContext = modelContext
        }
    }
    
    private func resolveStudent(id: String) -> Student? {
        // Simple lookup from the @Query array
        students.first { $0.id.uuidString == id }
    }
}

// MARK: - MeetingSummaryCard

struct MeetingSummaryCard: View {
    let meeting: StudentMeeting
    let student: Student?
    
    @State private var isExpanded: Bool = false
    @State private var summary: String? = nil
    @State private var isGenerating: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header (Always Visible)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let student {
                        Text("\(student.firstName) \(student.lastName)")
                            .font(.headline)
                    } else {
                        Text("Unknown Student")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(meeting.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            
            // MARK: Content
            ZStack(alignment: .topLeading) {
                if isExpanded {
                    // Full Details View
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(title: "Focus", text: meeting.focus)
                        detailRow(title: "Reflection", text: meeting.reflection)
                        detailRow(title: "Requests", text: meeting.requests)
                        detailRow(title: "Guide Notes", text: meeting.guideNotes)
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // Summary View
                    summaryContent
                        .padding(12)
                        .transition(.opacity)
                }
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .task {
            // Auto-generate summary if not expanded and not yet generated
            if !isExpanded && summary == nil {
                await generateSummary()
            }
        }
    }
    
    private var summaryContent: some View {
        Group {
            if let summary {
                HStack(alignment: .top, spacing: 8) {
                    // Change icon color based on whether it's AI (Purple) or Manual (Gray)
                    Image(systemName: "sparkles")
                        .foregroundStyle(isAIEnabled ? .purple : .gray)
                        .font(.caption)
                        .padding(.top, 2)
                    
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Summarizing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Expand to see details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var isAIEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }
    
    private func detailRow(title: String, text: String) -> some View {
        Group {
            if !text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.body)
                }
            }
        }
    }
    
    private func generateSummary() async {
        let manualSummary = generateFallbackSummary()
        
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            setSummary(manualSummary)
            return
        }
        
        // Don't burn AI tokens if the content is very short
        let totalLength = meeting.reflection.count + meeting.guideNotes.count + meeting.focus.count
        guard totalLength > 30 else {
            setSummary(manualSummary)
            return
        }
        
        isGenerating = true
        
        let context = """
        Student Reflection: \(meeting.reflection)
        Focus: \(meeting.focus)
        Requests: \(meeting.requests)
        Guide Notes: \(meeting.guideNotes)
        """
        
        let instructions = "You are a Montessori guide assistant. Summarize this student meeting outcomes and sentiment in 2 sentences."
        let session = LanguageModelSession(instructions: instructions)
        
        do {
            let stream = session.streamResponse(
                to: "Summarize this meeting:\n\(context)",
                generating: MeetingSummary.self
            )
            
            for try await partial in stream {
                if let overview = partial.content.overview, !overview.isEmpty {
                    setSummary(overview)
                }
            }
        } catch {
            #if DEBUG
            print("AI Summary failed: \(error)")
            #endif
            setSummary(manualSummary)
        }
        isGenerating = false
        
        #else
        // Fallback: AI disabled
        setSummary(manualSummary)
        #endif
    }
    
    @MainActor
    private func setSummary(_ text: String) {
        withAnimation {
            self.summary = text
        }
    }
    
    private func generateFallbackSummary() -> String {
        var parts: [String] = []
        if !meeting.focus.isEmpty { parts.append("Focus: \(meeting.focus)") }
        if !meeting.reflection.isEmpty { parts.append("Reflection: \(meeting.reflection)") }
        if !meeting.requests.isEmpty { parts.append("Requests: \(meeting.requests)") }
        if !meeting.guideNotes.isEmpty { parts.append(meeting.guideNotes) }
        
        if parts.isEmpty { return "No details recorded." }
        return parts.joined(separator: " • ")
    }
}

#Preview {
    MeetingsAgendaView()
}
