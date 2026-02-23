import SwiftUI
import SwiftData

struct IssueDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Student.firstName) private var allStudents: [Student]
    
    let issue: Issue?
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var category: IssueCategory = .other
    @State private var priority: IssuePriority = .medium
    @State private var status: IssueStatus = .open
    @State private var selectedStudentIDs: Set<String> = []
    @State private var location: String = ""
    @State private var resolutionSummary: String = ""
    
    @State private var showingNewActionSheet = false
    @State private var selectedAction: IssueAction?
    
    var isEditing: Bool { issue != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section("Details") {
                    TextField("Title", text: $title)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    Picker("Category", selection: $category) {
                        ForEach(IssueCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }
                    
                    Picker("Priority", selection: $priority) {
                        ForEach(IssuePriority.allCases, id: \.self) { pri in
                            Text(pri.rawValue).tag(pri)
                        }
                    }
                    
                    Picker("Status", selection: $status) {
                        ForEach(IssueStatus.allCases, id: \.self) { stat in
                            Label(stat.rawValue, systemImage: stat.systemImage)
                                .tag(stat)
                        }
                    }
                    
                    TextField("Location", text: $location)
                }
                
                // Related students
                Section("Related Students") {
                    ForEach(allStudents) { student in
                        Button {
                            toggleStudent(student.id.uuidString)
                        } label: {
                            HStack {
                                Text(student.firstName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStudentIDs.contains(student.id.uuidString) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                
                // Resolution
                if status == .resolved || status == .closed {
                    Section("Resolution") {
                        TextField("Resolution summary", text: $resolutionSummary, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                
                // Actions history (only when editing)
                if let issue = issue {
                    Section {
                        Button {
                            showingNewActionSheet = true
                        } label: {
                            Label("Add Action", systemImage: "plus.circle.fill")
                        }
                        
                        if let actions = issue.actions?.sorted(by: { $0.actionDate > $1.actionDate }) {
                            if actions.isEmpty {
                                Text("No actions recorded yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(actions) { action in
                                    IssueActionRowView(action: action)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedAction = action
                                        }
                                }
                                .onDelete { offsets in
                                    deleteActions(issue: issue, at: offsets)
                                }
                            }
                        }
                    } header: {
                        Text("Actions & Follow-ups")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Issue" : "New Issue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveIssue()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .sheet(isPresented: $showingNewActionSheet) {
                if let issue = issue {
                    IssueActionSheet(issue: issue, action: nil)
                }
            }
            .sheet(item: $selectedAction) { action in
                IssueActionSheet(issue: issue!, action: action)
            }
            .onAppear {
                loadIssueData()
            }
        }
    }
    
    private func loadIssueData() {
        guard let issue = issue else { return }
        title = issue.title
        description = issue.issueDescription
        category = issue.category
        priority = issue.priority
        status = issue.status
        selectedStudentIDs = Set(issue.studentIDs)
        location = issue.location ?? ""
        resolutionSummary = issue.resolutionSummary ?? ""
    }
    
    private func toggleStudent(_ studentID: String) {
        if selectedStudentIDs.contains(studentID) {
            selectedStudentIDs.remove(studentID)
        } else {
            selectedStudentIDs.insert(studentID)
        }
    }
    
    private func saveIssue() {
        if let issue = issue {
            // Update existing issue
            issue.title = title
            issue.issueDescription = description
            issue.category = category
            issue.priority = priority
            issue.status = status
            issue.studentIDs = Array(selectedStudentIDs)
            issue.location = location.isEmpty ? nil : location
            issue.resolutionSummary = resolutionSummary.isEmpty ? nil : resolutionSummary
            issue.updatedAt = Date()
            issue.modifiedAt = Date()
            
            if status == .resolved || status == .closed {
                if issue.resolvedAt == nil {
                    issue.resolvedAt = Date()
                }
            } else {
                issue.resolvedAt = nil
            }
        } else {
            // Create new issue
            let newIssue = Issue(
                title: title,
                description: description,
                category: category,
                priority: priority,
                status: status,
                studentIDs: Array(selectedStudentIDs),
                location: location.isEmpty ? nil : location
            )
            modelContext.insert(newIssue)
        }
        
        modelContext.safeSave()
        dismiss()
    }
    
    private func deleteActions(issue: Issue, at offsets: IndexSet) {
        guard let actions = issue.actions?.sorted(by: { $0.actionDate > $1.actionDate }) else { return }
        for index in offsets {
            modelContext.delete(actions[index])
        }
        modelContext.safeSave()
    }
}

struct IssueActionRowView: View {
    let action: IssueAction
    @Query private var allStudents: [Student]
    
    var participantNames: String {
        let students = allStudents.filter { action.participantStudentIDs.contains($0.id.uuidString) }
        return students.map { $0.firstName }.joined(separator: ", ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(action.actionType.rawValue, systemImage: action.actionType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(action.actionDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Text(action.actionDescription)
                .font(.subheadline)
            
            if !participantNames.isEmpty {
                HStack {
                    Image(systemName: "person.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(participantNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let nextSteps = action.nextSteps, !nextSteps.isEmpty {
                Label(nextSteps, systemImage: "arrow.turn.up.right")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            
            if action.followUpRequired {
                HStack {
                    Image(systemName: action.followUpCompleted ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(action.followUpCompleted ? .green : .orange)
                    if let followUpDate = action.followUpDate {
                        Text("Follow-up: \(followUpDate, style: .date)")
                    } else {
                        Text("Follow-up required")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct IssueActionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Student.firstName) private var allStudents: [Student]
    
    let issue: Issue
    let action: IssueAction?
    
    @State private var actionType: IssueActionType = .note
    @State private var description: String = ""
    @State private var actionDate: Date = Date()
    @State private var selectedStudentIDs: Set<String> = []
    @State private var nextSteps: String = ""
    @State private var followUpRequired: Bool = false
    @State private var followUpDate: Date = Date()
    @State private var followUpCompleted: Bool = false
    
    var isEditing: Bool { action != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Action Details") {
                    Picker("Type", selection: $actionType) {
                        ForEach(IssueActionType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    
                    DatePicker("Date", selection: $actionDate, displayedComponents: [.date, .hourAndMinute])
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                
                Section("Participants") {
                    ForEach(allStudents) { student in
                        Button {
                            toggleStudent(student.id.uuidString)
                        } label: {
                            HStack {
                                Text(student.firstName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStudentIDs.contains(student.id.uuidString) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section("Next Steps") {
                    TextField("Next steps or agreements", text: $nextSteps, axis: .vertical)
                        .lineLimit(2...4)
                    
                    Toggle("Follow-up required", isOn: $followUpRequired)
                    
                    if followUpRequired {
                        DatePicker("Follow-up date", selection: $followUpDate, displayedComponents: .date)
                        Toggle("Follow-up completed", isOn: $followUpCompleted)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Action" : "New Action")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAction()
                    }
                    .disabled(description.isEmpty)
                }
            }
            .onAppear {
                loadActionData()
            }
        }
    }
    
    private func loadActionData() {
        guard let action = action else { return }
        actionType = action.actionType
        description = action.actionDescription
        actionDate = action.actionDate
        selectedStudentIDs = Set(action.participantStudentIDs)
        nextSteps = action.nextSteps ?? ""
        followUpRequired = action.followUpRequired
        followUpDate = action.followUpDate ?? Date()
        followUpCompleted = action.followUpCompleted
    }
    
    private func toggleStudent(_ studentID: String) {
        if selectedStudentIDs.contains(studentID) {
            selectedStudentIDs.remove(studentID)
        } else {
            selectedStudentIDs.insert(studentID)
        }
    }
    
    private func saveAction() {
        if let action = action {
            // Update existing action
            action.actionType = actionType
            action.actionDescription = description
            action.actionDate = actionDate
            action.participantStudentIDs = Array(selectedStudentIDs)
            action.nextSteps = nextSteps.isEmpty ? nil : nextSteps
            action.followUpRequired = followUpRequired
            action.followUpDate = followUpRequired ? followUpDate : nil
            action.followUpCompleted = followUpCompleted
            action.updatedAt = Date()
            action.modifiedAt = Date()
        } else {
            // Create new action
            let newAction = IssueAction(
                issue: issue,
                actionType: actionType,
                description: description,
                actionDate: actionDate,
                participantStudentIDs: Array(selectedStudentIDs),
                nextSteps: nextSteps.isEmpty ? nil : nextSteps,
                followUpRequired: followUpRequired,
                followUpDate: followUpRequired ? followUpDate : nil
            )
            modelContext.insert(newAction)
        }
        
        modelContext.safeSave()
        dismiss()
    }
}

#Preview("Issue List") {
    NavigationStack {
        IssuesListView()
    }
    .previewEnvironment()
}

#Preview("New Issue") {
    IssueDetailSheet(issue: nil)
        .previewEnvironment()
}
