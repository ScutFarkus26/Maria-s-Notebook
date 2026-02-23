import SwiftUI
import SwiftData

/// A reusable pill component for displaying WorkCheckIn entries in calendars
struct WorkCheckInPill: View {
    @Environment(\.modelContext) private var modelContext
    
    let checkIn: WorkCheckIn
    var isDulled: Bool = false
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: Name first, then lesson title
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !studentName.trimmed().isEmpty {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(workTitle)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            // Second row: purpose (e.g., Progress Check, Due Date)
            if !checkIn.purpose.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: purposeIcon)
                        .foregroundStyle(.secondary)
                    Text(checkIn.purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .opacity(isDulled ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
    
    // MARK: - Data Helpers
    
    private var workTitle: String {
        guard let workID = checkIn.workID.asUUID,
              let work = fetchWork(id: workID) else { return "Work" }
        
        if let lessonID = work.lessonID.asUUID {
            let descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
            if let lesson = modelContext.safeFetchFirst(descriptor) {
                let name = lesson.name.trimmed()
                if !name.isEmpty { return name }
            }
        }
        return "Lesson \(String(work.lessonID.prefix(6)))"
    }
    
    private var studentName: String {
        guard let workID = checkIn.workID.asUUID,
              let work = fetchWork(id: workID),
              let studentID = work.studentID.asUUID else { return "" }
        
        let descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
        if let student = modelContext.safeFetchFirst(descriptor) {
            return StudentFormatter.displayName(for: student)
        }
        return ""
    }
    
    private var purposeIcon: String {
        let purpose = checkIn.purpose.lowercased()
        if purpose.contains("progress") || purpose.contains("check") {
            return "checkmark.circle"
        } else if purpose.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if purpose.contains("assessment") {
            return "chart.bar"
        } else if purpose.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }
    
    private func fetchWork(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return modelContext.safeFetchFirst(descriptor)
    }
}
