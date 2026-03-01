import SwiftUI
import SwiftData

/// Main list view for all practice sessions
struct PracticeSessionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeSession.date, order: .reverse) private var allSessions: [PracticeSession]
    @Query private var allStudents: [Student]
    
    @State private var searchText: String = ""
    @State private var selectedFilter: FilterType = .all
    @State private var selectedStudent: UUID?
    @State private var showingDateRange: Bool = false
    @State private var dateRangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateRangeEnd: Date = Date()
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case group = "Group"
        case solo = "Solo"
        case today = "Today"
        case thisWeek = "This Week"
    }
    
    private var filteredSessions: [PracticeSession] {
        var sessions = allSessions
        
        // Apply filter type
        switch selectedFilter {
        case .all:
            break
        case .group:
            sessions = sessions.filter { $0.isGroupSession }
        case .solo:
            sessions = sessions.filter { $0.isSoloSession }
        case .today:
            let today = AppCalendar.startOfDay(Date())
            sessions = sessions.filter { AppCalendar.startOfDay($0.date) == today }
        case .thisWeek:
            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
            sessions = sessions.filter { $0.date >= weekStart && $0.date < weekEnd }
        }
        
        // Apply student filter
        if let studentID = selectedStudent {
            sessions = sessions.filter { $0.includes(studentID: studentID) }
        }
        
        // Apply search
        if !searchText.isEmpty {
            sessions = sessions.filter { session in
                session.sharedNotes.localizedCaseInsensitiveContains(searchText) ||
                session.location?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        return sessions
    }
    
    private var sessionsByDate: [(date: Date, sessions: [PracticeSession])] {
        let grouped = Dictionary(grouping: filteredSessions) { session in
            AppCalendar.startOfDay(session.date)
        }
        
        return grouped.map { (date: $0.key, sessions: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    private var totalDuration: TimeInterval {
        filteredSessions.compactMap { $0.duration }.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Statistics header
            statisticsHeader
            
            Divider()
            
            // Filters
            filtersSection
            
            Divider()
            
            // Sessions list
            if filteredSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                        ForEach(sessionsByDate, id: \.date) { dateGroup in
                            Section {
                                VStack(spacing: 12) {
                                    ForEach(dateGroup.sessions) { session in
                                        PracticeSessionCard(
                                            session: session,
                                            displayMode: .standard
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            } header: {
                                HStack {
                                    Text(formatDateHeader(dateGroup.date))
                                        .font(AppTheme.ScaledFont.captionSemibold)
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    
                                    Spacer()
                                    
                                    Text("\(dateGroup.sessions.count) session\(dateGroup.sessions.count == 1 ? "" : "s")")
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(.bar)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search notes or location")
        .navigationTitle("Practice Sessions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    // MARK: - Statistics Header
    
    private var statisticsHeader: some View {
        HStack(spacing: 20) {
            statBox(
                value: "\(filteredSessions.count)",
                label: "Sessions",
                icon: "calendar",
                color: .blue
            )
            
            Divider()
                .frame(height: 40)
            
            statBox(
                value: "\(filteredSessions.filter { $0.isGroupSession }.count)",
                label: "Group",
                icon: "person.2.fill",
                color: .green
            )
            
            Divider()
                .frame(height: 40)
            
            if totalDuration > 0 {
                statBox(
                    value: formatDuration(totalDuration),
                    label: "Time",
                    icon: "clock.fill",
                    color: .orange
                )
            } else {
                statBox(
                    value: "\(filteredSessions.filter { $0.isSoloSession }.count)",
                    label: "Solo",
                    icon: "person.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color.primary.opacity(0.03))
    }
    
    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
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
    
    // MARK: - Filters Section
    
    private var filtersSection: some View {
        VStack(spacing: 12) {
            // Filter type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterType.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal)
            }
            
            // Student filter
            if !allStudents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // All students chip
                        Button {
                            selectedStudent = nil
                        } label: {
                            HStack(spacing: 6) {
                                if selectedStudent == nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text("All Students")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(selectedStudent == nil ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedStudent == nil ? Color.accentColor : Color.primary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(allStudents.sorted(by: StudentSortComparator.byFirstName)) { student in
                            studentChip(student)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }
    
    private func filterChip(_ filter: FilterType) -> some View {
        Button {
            adaptiveWithAnimation {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                if selectedFilter == filter {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(filter.rawValue)
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(selectedFilter == filter ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedFilter == filter ? Color.blue : Color.primary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func studentChip(_ student: Student) -> some View {
        Button {
            if selectedStudent == student.id {
                selectedStudent = nil
            } else {
                selectedStudent = student.id
            }
        } label: {
            HStack(spacing: 6) {
                if selectedStudent == student.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(selectedStudent == student.id ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedStudent == student.id ? Color.accentColor : Color.primary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            Text(searchText.isEmpty ? "No Practice Sessions" : "No Results Found")
                .font(AppTheme.ScaledFont.titleSmall)
                .foregroundStyle(.secondary)
            
            Text(emptyStateMessage)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try adjusting your search or filters"
        }
        
        switch selectedFilter {
        case .all:
            return "Practice sessions will appear here once recorded"
        case .group:
            return "No group practice sessions found"
        case .solo:
            return "No solo practice sessions found"
        case .today:
            return "No practice sessions recorded today"
        case .thisWeek:
            return "No practice sessions this week"
        }
    }
    
    // MARK: - Helpers
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = AppCalendar.startOfDay(Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = Int(duration / 60)
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview("Practice Sessions List") {
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
    let work2 = WorkModel(title: "Fractions", studentID: mary.id.uuidString, lessonID: UUID().uuidString)
    
    context.insert(work1)
    context.insert(work2)
    
    // Create sample sessions
    for i in 0..<10 {
        let isGroup = i % 3 == 0
        let session = PracticeSession(
            date: Date().addingTimeInterval(Double(-i * 86400)),
            duration: Double((15 + i * 5) * 60),
            studentIDs: isGroup ? [danny.id.uuidString, mary.id.uuidString] : [danny.id.uuidString],
            workItemIDs: [work1.id.uuidString],
            sharedNotes: isGroup ? "Great teamwork! Both students improving." : "Making steady progress.",
            location: i % 2 == 0 ? "Classroom" : "Small table"
        )
        context.insert(session)
    }
    
    return NavigationStack {
        PracticeSessionsListView()
    }
    .modelContainer(container)
}
