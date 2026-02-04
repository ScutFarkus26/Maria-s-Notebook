import SwiftUI
import SwiftData

/// Display card for a practice session
struct PracticeSessionCard: View {
    let session: PracticeSession
    let displayMode: DisplayMode
    var onTap: (() -> Void)? = nil
    
    @Query private var allStudents: [Student]
    @Query private var allWork: [WorkModel]
    
    enum DisplayMode {
        case compact    // Minimal display
        case standard   // Normal card
        case expanded   // Full details
    }
    
    private var students: [Student] {
        allStudents.filter { student in
            session.studentIDs.contains(student.id.uuidString)
        }.sorted { $0.firstName < $1.firstName }
    }
    
    private var workItems: [WorkModel] {
        allWork.filter { work in
            session.workItemIDs.contains(work.id.uuidString)
        }
    }
    
    var body: some View {
        switch displayMode {
        case .compact:
            compactView
        case .standard:
            standardView
        case .expanded:
            expandedView
        }
    }
    
    // MARK: - Compact View
    
    private var compactView: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Session type icon
                Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(session.isGroupSession ? .blue : .secondary)
                
                // Date
                Text(formatDate(session.date))
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                
                // Student names
                Text(studentNames)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Duration if available
                if let duration = session.durationFormatted {
                    Text(duration)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Standard View
    
    private var standardView: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 12) {
                sessionHeader
                
                // Students
                HStack(spacing: 6) {
                    ForEach(students) { student in
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        if student.id != students.last?.id {
                            Text("&")
                                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Notes preview
                if !session.sharedNotes.isEmpty {
                    Text(session.sharedNotes)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .italic()
                }
                
                // Footer metadata
                HStack(spacing: 12) {
                    if let duration = session.durationFormatted {
                        Label(duration, systemImage: "clock.fill")
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let location = session.location, !location.isEmpty {
                        Label(location, systemImage: "location.fill")
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Work items count
                    if session.workItemCount > 1 {
                        Text("\(session.workItemCount) items")
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(session.isGroupSession ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Expanded View
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            expandedHeader
            Divider()
            
            // Students section
            VStack(alignment: .leading, spacing: 8) {
                Text("Participants")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                ForEach(students) { student in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 8, height: 8)
                        
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }
                }
            }
            
            // Work items section
            if !workItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Work Items")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    ForEach(workItems, id: \.id) { work in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 8, height: 8)
                            
                            Text(work.title)
                                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        }
                    }
                }
            }
            
            // Session notes
            if !session.sharedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(session.sharedNotes)
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            
            // Metadata footer
            HStack(spacing: 16) {
                if let duration = session.durationFormatted {
                    Label(duration, systemImage: "clock.fill")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                if let location = session.location, !location.isEmpty {
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(session.isGroupSession ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }
    
    // MARK: - Standard View Components
    
    private var expandedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(session.isGroupSession ? .blue : .secondary)
                    
                    Text(session.isGroupSession ? "Group Practice Session" : "Solo Practice Session")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                }
                
                Text(formatDateLong(session.date))
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var sessionHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                    .font(.system(size: 10))
                Text(session.isGroupSession ? "Group" : "Solo")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(session.isGroupSession ? Color.blue : Color.gray)
            )
            
            Spacer()
            
            Text(formatDate(session.date))
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Helpers
    
    private var studentNames: String {
        students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", ")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatDateLong(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Practice Session Cards") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    // Create sample students
    let mary = Student(firstName: "Mary", lastName: "Smith", birthday: Date(), level: .lower)
    let danny = Student(firstName: "Danny", lastName: "Jones", birthday: Date(), level: .lower)
    
    context.insert(mary)
    context.insert(danny)
    
    // Create sample lesson
    let lesson = Lesson()
    lesson.name = "Long Division"
    context.insert(lesson)
    
    // Create sample work
    let work1 = WorkModel(
        title: "Practice Long Division",
        studentID: danny.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work2 = WorkModel(
        title: "Practice Long Division",
        studentID: mary.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    
    context.insert(work1)
    context.insert(work2)
    
    // Create sample sessions
    let groupSession = PracticeSession(
        date: Date(),
        duration: 1800, // 30 minutes
        studentIDs: [danny.id.uuidString, mary.id.uuidString],
        workItemIDs: [work1.id.uuidString, work2.id.uuidString],
        sharedNotes: "Both students struggled with remainders but showed improvement by the end. Need more practice with manipulatives.",
        location: "Small table"
    )
    
    let soloSession = PracticeSession(
        date: Date().addingTimeInterval(-86400), // Yesterday
        duration: 900, // 15 minutes
        studentIDs: [danny.id.uuidString],
        workItemIDs: [work1.id.uuidString],
        sharedNotes: "Quick review session. Danny is getting better!",
        location: nil
    )
    
    context.insert(groupSession)
    context.insert(soloSession)
    
    return ScrollView {
        VStack(spacing: 20) {
            Text("Compact")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .compact)
            
            Text("Standard")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .standard)
            
            Text("Expanded")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .expanded)
            
            Text("Solo Session")
                .font(.headline)
            PracticeSessionCard(session: soloSession, displayMode: .standard)
        }
        .padding()
    }
    .modelContainer(container)
}
