import SwiftUI
import SwiftData

/// A reusable pill component for displaying WorkPlanItem entries in calendars
struct WorkPlanItemPill: View {
    @Environment(\.modelContext) private var modelContext
    
    let item: WorkPlanItem
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
            // Second row: kind/reason (e.g., Check-In, Due)
            if let reasonText = reasonLabel {
                HStack(spacing: 6) {
                    if let r = item.reason { 
                        Image(systemName: r.icon)
                            .foregroundStyle(.secondary)
                    }
                    Text(reasonText)
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
        .draggable(UnifiedCalendarDragPayload.workPlanItem(item.id).stringRepresentation) {
            WorkPlanItemPill(item: item, isDulled: isDulled, onTap: onTap)
                .opacity(0.9)
        }
    }
    
    // MARK: - Data Helpers
    
    private var workTitle: String {
        guard let workID = item.workID.asUUID,
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
        guard let workID = item.workID.asUUID,
              let work = fetchWork(id: workID),
              let studentID = work.studentID.asUUID else { return "" }
        
        let descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
        if let student = modelContext.safeFetchFirst(descriptor) {
            return StudentFormatter.displayName(for: student)
        }
        return ""
    }
    
    private var reasonLabel: String? {
        guard let reason = item.reason else { return nil }
        switch reason {
        case .progressCheck:
            return WorkScheduleDateLogic.label(for: .checkIn)
        case .dueDate:
            return WorkScheduleDateLogic.label(for: .due)
        default:
            return reason.label
        }
    }
    
    private func fetchWork(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return modelContext.safeFetchFirst(descriptor)
    }
}
