import SwiftUI
import SwiftData

struct BookClubsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\BookClub.createdAt, order: .reverse)]) private var clubs: [BookClub]
    @Query(sort: [SortDescriptor<BookClubTemplateWeek>(\.weekIndex, order: .forward)]) private var allWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor<BookClubChoiceItem>(\.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor<BookClubChoiceSet>(\.createdAt, order: .forward)]) private var allChoiceSets: [BookClubChoiceSet]
    @Query(sort: [SortDescriptor<BookClubWeekRoleAssignment>(\.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]
    @Query(sort: [SortDescriptor<BookClubRole>(\.createdAt, order: .forward)]) private var allRoles: [BookClubRole]
    @Query(sort: [SortDescriptor<BookClubSession>(\.createdAt, order: .forward)]) private var allSessions: [BookClubSession]
    @Query(sort: [SortDescriptor<BookClubAssignmentTemplate>(\.createdAt, order: .forward)]) private var allTemplates: [BookClubAssignmentTemplate]

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
                        .contextMenu {
                            Button("Delete", role: .destructive) { deleteClub(club) }
                        }
                    }
                    .onDelete(perform: deleteAtOffsets)
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

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for i in offsets {
            if clubs.indices.contains(i) {
                let club = clubs[i]
                deleteClub(club)
            }
        }
    }

    private func deleteClub(_ club: BookClub) {
        // Delete sessions and their deliverables
        let sessions = allSessions.filter { $0.bookClubID == club.id }
        for s in sessions {
            for d in s.deliverables {
                modelContext.delete(d)
            }
            modelContext.delete(s)
        }

        // Delete templates associated with this club
        let templates = allTemplates.filter { $0.bookClubID == club.id }
        for t in templates { modelContext.delete(t) }

        // Delete roles for this club
        let roles = allRoles.filter { $0.bookClubID == club.id }
        for r in roles { modelContext.delete(r) }

        // Delete template weeks and their related data
        let weeks = allWeeks.filter { $0.bookClubID == club.id }
        for w in weeks {
            // Role assignments for the week
            let assigns = allRoleAssignments.filter { $0.weekID == w.id }
            for a in assigns { modelContext.delete(a) }
            // Choice set and items referenced by the week
            if let setID = w.questionChoiceSetID {
                let items = allChoiceItems.filter { $0.setID == setID }
                for item in items { modelContext.delete(item) }
                if let set = allChoiceSets.first(where: { $0.id == setID }) { modelContext.delete(set) }
            }
            modelContext.delete(w)
        }

        // Delete any standalone choice sets/items that belong to this club (safety cleanup)
        let sets = allChoiceSets.filter { $0.bookClubID == club.id }
        for set in sets {
            let items = allChoiceItems.filter { $0.setID == set.id }
            for item in items { modelContext.delete(item) }
            modelContext.delete(set)
        }

        // Finally, delete the club itself
        modelContext.delete(club)
        _ = saveCoordinator.save(modelContext, reason: "Delete Book Club")
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

