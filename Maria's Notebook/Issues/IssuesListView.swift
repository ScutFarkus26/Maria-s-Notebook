import SwiftUI
import SwiftData

struct IssuesListView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Issue.createdAt, order: .reverse) private var allIssues: [Issue]
    
    @State private var selectedIssue: Issue?
    @State private var showingNewIssueSheet = false
    @State private var filterStatus: IssueStatus?
    @State private var filterCategory: IssueCategory?
    @State private var searchText = ""
    
    var filteredIssues: [Issue] {
        allIssues.filter { issue in
            // Filter by status
            if let filterStatus = filterStatus, issue.status != filterStatus {
                return false
            }
            
            // Filter by category
            if let filterCategory = filterCategory, issue.category != filterCategory {
                return false
            }
            
            // Filter by search text
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return issue.title.lowercased().contains(searchLower) ||
                       issue.issueDescription.lowercased().contains(searchLower)
            }
            
            return true
        }
    }
    
    var body: some View {
        List {
            // Summary stats
            Section {
                HStack(spacing: 20) {
                    IssueStatCard(
                        title: "Open",
                        count: allIssues.filter { $0.status == .open }.count,
                        color: .blue
                    )
                    IssueStatCard(
                        title: "In Progress",
                        count: allIssues.filter { $0.status == .inProgress || $0.status == .investigating }.count,
                        color: .orange
                    )
                    IssueStatCard(
                        title: "Resolved",
                        count: allIssues.filter { $0.status == .resolved }.count,
                        color: .green
                    )
                }
                .padding(.vertical, 8)
            }
            
            // Filters
            Section("Filters") {
                Picker("Status", selection: $filterStatus) {
                    Text("All").tag(nil as IssueStatus?)
                    ForEach(IssueStatus.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.systemImage)
                            .tag(status as IssueStatus?)
                    }
                }
                
                Picker("Category", selection: $filterCategory) {
                    Text("All").tag(nil as IssueCategory?)
                    ForEach(IssueCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.systemImage)
                            .tag(category as IssueCategory?)
                    }
                }
            }
            
            // Issues list
            Section {
                if filteredIssues.isEmpty {
                    ContentUnavailableView(
                        "No Issues",
                        systemImage: "checkmark.circle",
                        description: Text("No issues match your filters")
                    )
                } else {
                    ForEach(filteredIssues) { issue in
                        IssueRowView(issue: issue)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIssue = issue
                            }
                    }
                    .onDelete(perform: deleteIssues)
                }
            }
        }
        .navigationTitle("Issues")
        .searchable(text: $searchText, prompt: "Search issues")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewIssueSheet = true
                } label: {
                    Label("New Issue", systemImage: "plus")
                }
            }
        }
        .sheet(item: $selectedIssue) { issue in
            IssueDetailSheet(issue: issue)
        }
        .sheet(isPresented: $showingNewIssueSheet) {
            IssueDetailSheet(issue: nil)
        }
    }
    
    private func deleteIssues(at offsets: IndexSet) {
        for index in offsets {
            let issue = filteredIssues[index]
            modelContext.delete(issue)
        }
        modelContext.safeSave()
    }
}

struct IssueStatCard: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IssueRowView: View {
    let issue: Issue
    @Query private var allStudents: [Student]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(issue.category.rawValue, systemImage: issue.category.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Label(issue.priority.rawValue, systemImage: "exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color(issue.priority.color))
            }
            
            Text(issue.title)
                .font(.headline)
            
            if !issue.issueDescription.isEmpty {
                Text(issue.issueDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Label(issue.status.rawValue, systemImage: issue.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !issue.studentIDs.isEmpty {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(issue.studentIDs.count) student\(issue.studentIDs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let actions = issue.actions, !actions.isEmpty {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(actions.count) action\(actions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(issue.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        IssuesListView()
            .previewEnvironment()
    }
}
