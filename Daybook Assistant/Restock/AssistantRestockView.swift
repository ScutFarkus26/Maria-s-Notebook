import SwiftUI
import CoreData

/// The Restock tab: the Office run banner, then the shelf, two columns of
/// tiles grouped by where things live (one at accessibility text sizes, as
/// the attendance grid does, so a name isn't broken mid-word). A tap says
/// something is running out; holding a tile gives every level, a note and its
/// history. The + asks for something that isn't on the shelf ("We need…").
struct AssistantRestockView: View {
    let model: AssistantRestockModel

    @State private var showingClassroom = false
    @State private var showingWeNeed = false
    @State private var noteStaple: CDSupply?
    @State private var historyStaple: CDSupply?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tap a tile when something runs low")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                    officeRunBanner
                        .padding(.top, 14)
                    if model.shelf.isEmpty {
                        emptyShelf
                    } else {
                        shelf
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Restock")
            .toolbar { toolbar }
            .refreshable { model.load() }
            .navigationDestination(for: AssistantRestockRoute.self) { _ in
                AssistantOfficeRunView(model: model)
            }
        }
        .tint(AssistantRestockStyle.accent)
        .sheet(isPresented: $showingClassroom) {
            AssistantClassroomSheet()
        }
        .sheet(isPresented: $showingWeNeed) {
            AssistantWeNeedSheet(model: model)
        }
        .sheet(item: $noteStaple) { staple in
            AttendanceNoteSheet(
                studentName: staple.name,
                initialText: staple.notes,
                sharedWith: model.seesNoteToo,
                onSave: { model.setNote($0, for: staple) }
            )
        }
        .sheet(item: $historyStaple) { staple in
            AssistantRestockHistorySheet(model: model, staple: staple)
        }
        .onAppear { model.load() }
        .onDisappear { model.flush() }
    }

    // MARK: - Pieces

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingWeNeed = true
            } label: {
                Label("We need…", systemImage: "plus")
            }
            .accessibilityHint("Ask for something that isn't on the shelf")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingClassroom = true
            } label: {
                Label("Classroom", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityHint("Your guide, your name, and leaving the classroom")
        }
    }

    /// "Office run · 3" and what's on it, pushing to the run.
    private var officeRunBanner: some View {
        NavigationLink(value: AssistantRestockRoute.officeRun) {
            HStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.officeRunCount > 0 ? "Office run · \(model.officeRunCount)" : "Office run")
                        .font(.headline)
                    Text(runLine)
                        .font(.footnote)
                        .opacity(0.85)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(AssistantRestockStyle.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(AssistantRestockStyle.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "Toilet Paper, Paper Towels, Glue sticks", or nothing to grab.
    private var runLine: String {
        let open = model.officeRun.filter { !model.isCheckedOff($0) }
        guard !open.isEmpty else {
            return model.ordering.isEmpty ? "Nothing to grab right now" : "Nothing to grab · see what's ordered"
        }
        return open.map(\.displayTitle).joined(separator: ", ")
    }

    private var shelf: some View {
        ForEach(model.shelf) { group in
            Text(group.title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(group.staples, id: \.objectID) { staple in
                    tile(staple)
                }
            }
        }
    }

    private func tile(_ staple: CDSupply) -> some View {
        // Read so a change made here (whose staple is the same object) redraws.
        _ = model.revision
        return AssistantRestockTile(
            name: staple.name,
            level: staple.level,
            markedBy: model.markedBy(staple),
            hasNote: !staple.notes.isEmpty,
            menuHeader: model.menuHeader(staple),
            onTap: { model.tap(staple) },
            onSetLevel: { model.setLevel(staple, to: $0) },
            onNote: { noteStaple = staple },
            onHistory: { historyStaple = staple }
        )
    }

    private var emptyShelf: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing on the shelf yet")
                .font(.headline)
            Text(model.emptyShelfMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

/// Where the Restock tab pushes to.
enum AssistantRestockRoute: Hashable {
    case officeRun
}
