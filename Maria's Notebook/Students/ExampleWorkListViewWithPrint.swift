import SwiftUI
import SwiftData

/// Example integration showing how to add print functionality to your Work view.
/// This demonstrates the pattern you can follow in your actual WorkAgendaView or similar.

// MARK: - Example Work List View with Print

struct ExampleWorkListViewWithPrint: View {
    @Environment(\.modelContext) private var modelContext
    
    // Queries
    @Query(sort: \WorkModel.assignedAt, order: .reverse)
    private var allWork: [WorkModel]
    
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    // Filter and sort state
    @State private var filterStatus: WorkStatusFilter = .openOnly
    @State private var sortOrder: WorkSortOrder = .dueDate
    @State private var searchText: String = ""
    
    // Computed filtered and sorted work
    private var displayedWork: [WorkModel] {
        var filtered = allWork
        
        // Apply status filter
        switch filterStatus {
        case .openOnly:
            filtered = filtered.filter { $0.isOpen }
        case .active:
            filtered = filtered.filter { $0.status == .active }
        case .review:
            filtered = filtered.filter { $0.status == .review }
        case .complete:
            filtered = filtered.filter { $0.status == .complete }
        case .all:
            break
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { work in
                // Search in title
                if work.title.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in lesson name
                if let lessonID = UUID(uuidString: work.lessonID),
                   let lesson = lessons.first(where: { $0.id == lessonID }),
                   lesson.name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in student name
                if let studentID = UUID(uuidString: work.studentID),
                   let student = students.first(where: { $0.id == studentID }),
                   student.fullName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                return false
            }
        }
        
        // Apply sorting
        return sortOrder.sort(filtered, lessons: lessons, students: students)
    }
    
    // Filter and sort descriptions for print view
    private var filterDescription: String {
        var parts: [String] = []
        
        switch filterStatus {
        case .openOnly: parts.append("Open items only")
        case .active: parts.append("Status: Active")
        case .review: parts.append("Status: Review")
        case .complete: parts.append("Status: Complete")
        case .all: parts.append("All items")
        }
        
        if !searchText.isEmpty {
            parts.append("Search: \"\(searchText)\"")
        }
        
        return parts.joined(separator: " • ")
    }
    
    private var sortDescription: String {
        sortOrder.description
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(displayedWork) { work in
                    WorkRowView(
                        work: work,
                        student: students.first { $0.id.uuidString == work.studentID },
                        lesson: lessons.first { $0.id.uuidString == work.lessonID }
                    )
                }
            }
            .navigationTitle("Open Work")
            .searchable(text: $searchText, prompt: "Search work items")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Filter", selection: $filterStatus) {
                            ForEach(WorkStatusFilter.allCases) { filter in
                                Label(filter.displayName, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }
                        
                        Divider()
                        
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(WorkSortOrder.allCases) { order in
                                Text(order.displayName)
                                    .tag(order)
                            }
                        }
                    } label: {
                        Label("Filter & Sort", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    
                    WorkPrintButton(
                        workItems: displayedWork,
                        students: students,
                        lessons: lessons,
                        filterDescription: filterDescription,
                        sortDescription: sortDescription
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum WorkStatusFilter: String, CaseIterable, Identifiable {
    case openOnly = "Open Only"
    case active = "Active"
    case review = "Review"
    case complete = "Complete"
    case all = "All"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .openOnly: return "tray"
        case .active: return "circle"
        case .review: return "exclamationmark.circle"
        case .complete: return "checkmark.circle"
        case .all: return "square.stack"
        }
    }
}

enum WorkSortOrder: String, CaseIterable, Identifiable {
    case dueDate = "Due Date"
    case assignedDate = "Assigned Date"
    case studentName = "Student Name"
    case lessonName = "Lesson Name"
    case workKind = "Work Kind"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var description: String { "By \(rawValue)" }
    
    func sort(_ work: [WorkModel], lessons: [Lesson], students: [Student]) -> [WorkModel] {
        switch self {
        case .dueDate:
            return work.sorted { w1, w2 in
                // Items with due dates come first
                switch (w1.dueAt, w2.dueAt) {
                case (let d1?, let d2?):
                    return d1 < d2
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return w1.assignedAt < w2.assignedAt
                }
            }
            
        case .assignedDate:
            return work.sorted { $0.assignedAt > $1.assignedAt }
            
        case .studentName:
            return work.sorted { w1, w2 in
                let name1 = students.first { $0.id.uuidString == w1.studentID }?.fullName ?? ""
                let name2 = students.first { $0.id.uuidString == w2.studentID }?.fullName ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
            
        case .lessonName:
            return work.sorted { w1, w2 in
                let name1 = lessons.first { $0.id.uuidString == w1.lessonID }?.name ?? ""
                let name2 = lessons.first { $0.id.uuidString == w2.lessonID }?.name ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
            
        case .workKind:
            return work.sorted { w1, w2 in
                let kind1 = w1.kind?.displayName ?? ""
                let kind2 = w2.kind?.displayName ?? ""
                if kind1 != kind2 {
                    return kind1.localizedCaseInsensitiveCompare(kind2) == .orderedAscending
                }
                return w1.assignedAt < w2.assignedAt
            }
        }
    }
}

// MARK: - Simple Work Row View

struct WorkRowView: View {
    let work: WorkModel
    let student: Student?
    let lesson: Lesson?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let lesson = lesson {
                    Circle()
                        .fill(AppColors.color(forSubject: lesson.subject))
                        .frame(width: 8, height: 8)
                    
                    Text(lesson.name)
                        .font(.headline)
                } else {
                    Text("Lesson")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let dueAt = work.dueAt {
                    Text(dueAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(dueAt < Date() ? .red : .secondary)
                }
            }
            
            if let student = student {
                Text(student.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if let kind = work.kind {
                Text(kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !work.title.isEmpty {
                Text(work.title)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Work List with Print") {
    ExampleWorkListViewWithPrint()
        .previewEnvironment()
}
