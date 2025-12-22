import SwiftUI
import SwiftData

struct BookClubsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\BookClub.createdAt, order: .reverse)]) private var clubs: [BookClub]

    @State private var showNewSheet: Bool = false

    private static let df: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()

    var body: some View {
        Group {
            if clubs.isEmpty {
                ContentUnavailableView("No Book Clubs", systemImage: "book", description: Text("Create your first book club to get started."))
            } else {
                List {
                    ForEach(clubs) { club in
                        NavigationLink {
                            BookClubDetailView(club: club)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(club.title)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        let members = club.memberStudentIDs.count
                                        Text("\(members) member\(members == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let last = lastSessionDate(for: club) {
                                            Text("•")
                                                .foregroundStyle(.secondary)
                                            Text("Last: \(Self.df.string(from: last))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Book Clubs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSheet = true
                } label: {
                    Label("New Book Club", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSheet) {
            BookClubEditorSheet(club: nil)
        }
        .navigationDestination(for: UUID.self) { id in
            if let club = clubs.first(where: { $0.id == id }) {
                BookClubDetailView(club: club)
            } else {
                ContentUnavailableView("Club not found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func lastSessionDate(for club: BookClub) -> Date? {
        club.sessions.map { $0.meetingDate }.max()
    }
}

#Preview {
    let schema = AppSchema.schema
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let club = BookClub(title: "Readers A")
    ctx.insert(club)

    return BookClubsRootView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}

