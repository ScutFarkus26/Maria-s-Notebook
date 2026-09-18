import SwiftUI
import CoreData

struct BookClubSessionsListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDBookClubSession.startDate, ascending: true),
            NSSortDescriptor(keyPath: \CDBookClubSession.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var sessions: FetchedResults<CDBookClubSession>

    @State private var viewModel = BookClubSessionsViewModel()
    @State private var selectedSessionID: NSManagedObjectID?
    @State private var isShowingEditor = false

    private var selectedSession: CDBookClubSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.objectID == id }
    }

    private var grouped: [(status: BookClubSessionStatus, sessions: [CDBookClubSession])] {
        viewModel.grouped(Array(sessions))
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if let session = selectedSession {
                Divider()
                BookClubSessionDetailView(
                    session: session,
                    onClose: { selectedSessionID = nil },
                    onDelete: { selectedSessionID = nil }
                )
                .frame(width: 520)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSessionID)
        .sheet(isPresented: $isShowingEditor) {
            BookClubSessionEditorSheet(prefilledPacket: nil)
                .frame(minWidth: 560, minHeight: 600)
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("Book Club Sessions")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                isShowingEditor = true
            } label: {
                Label("New Session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            List {
                ForEach(grouped, id: \.status) { group in
                    Section(group.status.displayName) {
                        ForEach(group.sessions, id: \.objectID) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func sessionRow(_ session: CDBookClubSession) -> some View {
        let packet = viewModel.packet(for: session, in: viewContext)
        let roster = viewModel.roster(for: session, in: viewContext)
        let next = viewModel.nextMeeting(for: session)
        let isSelected = session.objectID == selectedSessionID
        return Button {
            selectedSessionID = isSelected ? nil : session.objectID
        } label: {
            BookClubSessionRowView(
                session: session,
                packet: packet,
                roster: roster,
                nextMeeting: next
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.title3.weight(.semibold))
            Text("Start a new club from a packet, or use New Session.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
