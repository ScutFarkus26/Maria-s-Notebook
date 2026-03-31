// swiftlint:disable file_length
import SwiftUI
import CoreData

struct IssueDetailSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)])
    private var allStudents: FetchedResults<CDStudent>

    let issue: CDIssue?

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var category: IssueCategory = .other
    @State private var priority: IssuePriority = .medium
    @State private var status: IssueStatus = .open
    @State private var selectedStudentIDs: Set<String> = []
    @State private var location: String = ""
    @State private var resolutionSummary: String = ""

    @State private var showingNewActionSheet = false
    @State private var selectedAction: CDIssueAction?

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
                    ForEach(allStudents, id: \.objectID) { student in
                        let studentIDStr = student.id?.uuidString ?? ""
                        Button {
                            toggleStudent(studentIDStr)
                        } label: {
                            HStack {
                                Text(student.firstName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStudentIDs.contains(studentIDStr) {
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
                if let issue {
                    Section {
                        Button {
                            showingNewActionSheet = true
                        } label: {
                            Label("Add Action", systemImage: "plus.circle.fill")
                        }

                        let actionsArray = (issue.actions?.allObjects as? [CDIssueAction])?.sorted(by: {
                            ($0.actionDate ?? .distantPast) > ($1.actionDate ?? .distantPast)
                        }) ?? []
                        if actionsArray.isEmpty {
                            Text("No actions recorded yet")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(actionsArray, id: \.objectID) { action in
                                IssueActionRowView(action: action)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedAction = action
                                    }
                            }
                            .onDelete { offsets in
                                deleteActions(issue: issue, actions: actionsArray, at: offsets)
                            }
                        }
                    } header: {
                        Text("Actions & Follow-ups")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Issue" : "New Issue")
            .inlineNavigationTitle()
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
                if let issue {
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
        guard let issue else { return }
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
        if let issue {
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
            let newIssue = CDIssue(context: viewContext)
            newIssue.title = title
            newIssue.issueDescription = description
            newIssue.category = category
            newIssue.priority = priority
            newIssue.status = status
            newIssue.studentIDs = Array(selectedStudentIDs)
            newIssue.location = location.isEmpty ? nil : location
        }

        viewContext.safeSave()
        dismiss()
    }

    private func deleteActions(issue: CDIssue, actions: [CDIssueAction], at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(actions[index])
        }
        viewContext.safeSave()
    }
}

struct IssueActionRowView: View {
    let action: CDIssueAction

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)])
    private var allStudents: FetchedResults<CDStudent>

    var participantNames: String {
        let participantIDs = Set(action.participantStudentIDs)
        let students = allStudents.filter { student in
            guard let id = student.id else { return false }
            return participantIDs.contains(id.uuidString)
        }
        return students.map(\.firstName).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(action.actionType.rawValue, systemImage: action.actionType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let actionDate = action.actionDate {
                    Text(actionDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)])
    private var allStudents: FetchedResults<CDStudent>

    let issue: CDIssue
    let action: CDIssueAction?

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
                    ForEach(allStudents, id: \.objectID) { student in
                        let studentIDStr = student.id?.uuidString ?? ""
                        Button {
                            toggleStudent(studentIDStr)
                        } label: {
                            HStack {
                                Text(student.firstName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStudentIDs.contains(studentIDStr) {
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
            .inlineNavigationTitle()
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
        guard let action else { return }
        actionType = action.actionType
        description = action.actionDescription
        actionDate = action.actionDate ?? Date()
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
        if let action {
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
            let newAction = CDIssueAction(context: viewContext)
            newAction.issueID = issue.id?.uuidString ?? ""
            newAction.actionType = actionType
            newAction.actionDescription = description
            newAction.actionDate = actionDate
            newAction.participantStudentIDs = Array(selectedStudentIDs)
            newAction.nextSteps = nextSteps.isEmpty ? nil : nextSteps
            newAction.followUpRequired = followUpRequired
            newAction.followUpDate = followUpRequired ? followUpDate : nil
            newAction.issue = issue
        }

        viewContext.safeSave()
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
