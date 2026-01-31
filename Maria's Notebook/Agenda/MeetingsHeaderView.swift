import SwiftUI

struct MeetingsHeaderView: View {
    @Binding var filterDate: CommunityMeetingsView.DateFilter?
    let allTags: [String]
    @Binding var selectedTag: String?
    @Binding var searchText: String
    @Binding var showingAdd: Bool
    var onAddTopic: (String) -> Void

    var body: some View {
        ViewHeader(title: "Community") {
            HStack(spacing: 12) {
                Menu {
                    Section("Date") {
                        Button("All") { filterDate = nil }
                        Button("Today") { filterDate = .today }
                        Button("This Week") { filterDate = .thisWeek }
                        Button("This Month") { filterDate = .thisMonth }
                    }

                    Section("Tags") {
                        Button("All") { selectedTag = nil }
                        ForEach(allTags, id: \.self) { tag in
                            Button(tag) { selectedTag = tag }
                        }
                    }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)

                TextField("Search topics", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)

                Button("New Topic") {
                    let trimmed = searchText.trimmed()
                    if trimmed.isEmpty {
                        showingAdd = true
                    } else {
                        onAddTopic(trimmed)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
