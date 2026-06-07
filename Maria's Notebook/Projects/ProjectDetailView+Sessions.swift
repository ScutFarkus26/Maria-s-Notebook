import SwiftUI
import CoreData

extension ProjectDetailView {
    var sessionsSection: some View {
        SectionCard(title: "Project Check-Ins", systemImage: SFSymbol.Time.calendar) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Text("Observation, questions, and follow-up work")
                        .font(.headline)
                    Spacer()
                    Button {
                        showNewSession = true
                    } label: {
                        Label("New Check-In", systemImage: SFSymbol.Time.calendarBadgePlus)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if projectSessions.isEmpty {
                    Text("No check-ins yet")
                        .foregroundStyle(.secondary)
                        .padding(.top, AppTheme.Spacing.xsmall)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(projectSessions, id: \.objectID) { session in
                            NavigationLink {
                                ProjectSessionDetailView(session: session)
                            } label: {
                                SessionRow(
                                    session: session,
                                    questionCount: session.agendaItems.filter { !$0.trimmed().isEmpty }.count
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, AppTheme.Spacing.xsmall)
                            Divider().opacity(UIConstants.OpacityConstants.accent)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: CDProjectSession
    let questionCount: Int
    @FetchRequest private var workModels: FetchedResults<CDWorkModel>

    init(session: CDProjectSession, questionCount: Int) {
        self.session = session
        self.questionCount = questionCount
        let sid = session.id?.uuidString ?? ""
        _workModels = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "sourceContextID == %@", sid)
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(DateFormatters.mediumDate.string(from: session.meetingDate ?? Date()))
                    .font(.headline)
                if let focus = session.chapterOrPages, !focus.isEmpty {
                    Text(focus).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxsmall) {
                Text("\(workModels.count) follow-ups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(questionCount) next steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
