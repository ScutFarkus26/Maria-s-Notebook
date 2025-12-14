import SwiftUI

struct MeetingsHeaderView: View {
    @Binding var filterDate: CommunityMeetingsView.DateFilter?
    let allTags: [String]
    @Binding var selectedTag: String?
    @Binding var searchText: String
    @Binding var showingAdd: Bool
    var onAddTopic: (String) -> Void

    var body: some View {
        HStack {
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

            Spacer()

            TextField("Search topics", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Button("New Topic") {
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    showingAdd = true
                } else {
                    onAddTopic(trimmed)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(8)
    }
}
