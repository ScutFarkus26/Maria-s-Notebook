import SwiftUI
import SwiftData

/// View showing practice partnerships for a student
struct PracticePartnershipsView: View {
    let studentID: UUID
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [PracticeSession]
    @Query private var allStudents: [Student]
    
    @State private var selectedFilter: FilterType = .all
    
    enum FilterType: String, CaseIterable {
        case all = "All Sessions"
        case group = "Group Only"
        case solo = "Solo Only"
    }
    
    private var repository: PracticeSessionRepository {
        PracticeSessionRepository(modelContext: modelContext)
    }
    
    private var studentSessions: [PracticeSession] {
        let sessions = allSessions.filter { $0.includes(studentID: studentID) }
        
        switch selectedFilter {
        case .all:
            return sessions.sorted { $0.date > $1.date }
        case .group:
            return sessions.filter { $0.isGroupSession }.sorted { $0.date > $1.date }
        case .solo:
            return sessions.filter { $0.isSoloSession }.sorted { $0.date > $1.date }
        }
    }
    
    private var partnerships: [(partner: Student, sessionCount: Int)] {
        let partnerData = repository.fetchPartnerships(forStudentID: studentID)
        return partnerData.compactMap { (partnerID, count) in
            guard let partner = allStudents.first(where: { $0.id == partnerID }) else { return nil }
            return (partner, count)
        }
    }
    
    private var statistics: PracticeStatistics {
        repository.statistics(forStudentID: studentID)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Statistics summary
            statisticsCard
            
            // Practice partners
            if !partnerships.isEmpty {
                partnersCard
            }
            
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Sessions list
            if studentSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(studentSessions) { session in
                            PracticeSessionCard(session: session, displayMode: .standard)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Statistics Card
    
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Practice Statistics")
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }
            
            HStack(spacing: 20) {
                statItem(
                    value: "\(statistics.totalSessions)",
                    label: "Total Sessions",
                    icon: "calendar",
                    color: .blue
                )
                
                Divider()
                
                statItem(
                    value: "\(statistics.groupSessions)",
                    label: "Group",
                    icon: "person.2.fill",
                    color: .green
                )
                
                Divider()
                
                statItem(
                    value: "\(statistics.soloSessions)",
                    label: "Solo",
                    icon: "person.fill",
                    color: .orange
                )
            }
            .frame(maxWidth: .infinity)
            
            if statistics.totalDuration > 0 {
                HStack(spacing: 20) {
                    Label(statistics.totalDurationFormatted, systemImage: "clock.fill")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    
                    Label("Avg: \(statistics.averageDurationFormatted)", systemImage: "chart.line.uptrend.xyaxis")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal)
    }
    
    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(value)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(color)
            }
            
            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Partners Card
    
    private var partnersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AppColors.success)
                Text("Practice Partners")
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }
            
            ForEach(Array(partnerships.enumerated()), id: \.offset) { _, partnership in
                HStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 10, height: 10)
                    
                    Text(StudentFormatter.displayName(for: partnership.partner))
                        .font(AppTheme.ScaledFont.bodySemibold)
                    
                    Spacer()
                    
                    Text("\(partnership.sessionCount) session\(partnership.sessionCount == 1 ? "" : "s")")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.1))
                        )
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .all ? "person.2.slash" : "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text(emptyStateTitle)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.secondary)
            
            Text(emptyStateMessage)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all: return "No Practice Sessions Yet"
        case .group: return "No Group Sessions"
        case .solo: return "No Solo Sessions"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all: return "Practice sessions will appear here once recorded"
        case .group: return "Group practice sessions will appear here"
        case .solo: return "Solo practice sessions will appear here"
        }
    }
}

// MARK: - Standalone Sheet View

/// Full-screen view for practice partnerships
struct PracticePartnershipsSheet: View {
    let studentID: UUID
    let studentName: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            PracticePartnershipsView(studentID: studentID)
                .navigationTitle("\(studentName)'s Practice")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Compact Card View

/// Compact card showing practice summary for embedding in student profile
struct PracticePartnershipsSummaryCard: View {
    let studentID: UUID
    var onTapViewAll: (() -> Void)? = nil
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [PracticeSession]
    @Query private var allStudents: [Student]
    
    private var repository: PracticeSessionRepository {
        PracticeSessionRepository(modelContext: modelContext)
    }
    
    private var recentSessions: [PracticeSession] {
        allSessions
            .filter { $0.includes(studentID: studentID) }
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { $0 }
    }
    
    private var statistics: PracticeStatistics {
        repository.statistics(forStudentID: studentID)
    }
    
    private var topPartners: [(partner: Student, sessionCount: Int)] {
        let partnerData = repository.fetchPartnerships(forStudentID: studentID)
        return partnerData.compactMap { (partnerID, count) in
            guard let partner = allStudents.first(where: { $0.id == partnerID }) else { return nil }
            return (partner, count)
        }.prefix(3).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                    Text("Practice Sessions")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                }
                
                Spacer()
                
                if statistics.totalSessions > 0 {
                    Button {
                        onTapViewAll?()
                    } label: {
                        Text("View All")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            if statistics.totalSessions == 0 {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No practice sessions yet")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                // Stats summary
                HStack(spacing: 16) {
                    statBadge(value: "\(statistics.totalSessions)", label: "Total", color: .blue)
                    statBadge(value: "\(statistics.groupSessions)", label: "Group", color: .green)
                    statBadge(value: "\(statistics.soloSessions)", label: "Solo", color: .orange)
                }
                
                // Top partners
                if !topPartners.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Practice Partners")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        ForEach(Array(topPartners.enumerated()), id: \.offset) { _, partnership in
                            HStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 6, height: 6)
                                
                                Text(StudentFormatter.displayName(for: partnership.partner))
                                    .font(AppTheme.ScaledFont.caption)
                                
                                Spacer()
                                
                                Text("\(partnership.sessionCount)")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Recent sessions
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Sessions")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        ForEach(recentSessions) { session in
                            PracticeSessionCard(session: session, displayMode: .compact)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTheme.ScaledFont.titleSmall)
                .foregroundStyle(color)
            
            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview("Practice Partnerships View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    // Create sample students
    let danny = Student(firstName: "Danny", lastName: "Jones", birthday: Date(), level: .lower)
    let mary = Student(firstName: "Mary", lastName: "Smith", birthday: Date(), level: .lower)
    let jane = Student(firstName: "Jane", lastName: "Doe", birthday: Date(), level: .lower)
    
    context.insert(danny)
    context.insert(mary)
    context.insert(jane)
    
    // Create sample work
    let work1 = WorkModel(title: "Long Division", studentID: danny.id.uuidString, lessonID: UUID().uuidString)
    let work2 = WorkModel(title: "Long Division", studentID: mary.id.uuidString, lessonID: UUID().uuidString)
    
    context.insert(work1)
    context.insert(work2)
    
    // Create sample sessions
    for i in 0..<5 {
        let session = PracticeSession(
            date: Date().addingTimeInterval(Double(-i * 86400)),
            duration: 1800,
            studentIDs: i % 2 == 0 ? [danny.id.uuidString, mary.id.uuidString] : [danny.id.uuidString],
            workItemIDs: [work1.id.uuidString],
            sharedNotes: "Practice session \(i + 1)",
            location: "Classroom"
        )
        context.insert(session)
    }
    
    return PracticePartnershipsView(studentID: danny.id)
        .modelContainer(container)
}
