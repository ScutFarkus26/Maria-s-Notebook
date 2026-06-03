import SwiftUI
import CoreData

struct ProjectDetailView: View {
    let club: CDProject

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: CDStudent.sortByName) private var studentsRaw: FetchedResults<CDStudent>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var lessonsRaw: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var allWorkModels: FetchedResults<CDWorkModel>

    // Performance: Filter roles by projectID at query level
    @FetchRequest private var roles: FetchedResults<CDProjectRole>

    @State private var showNewSession: Bool = false
    @State private var showEditClub: Bool = false
    @State private var showManageRoles: Bool = false

    init(club: CDProject) {
        self.club = club
        let projectIDString = (club.id ?? UUID()).uuidString
        _roles = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectRole.createdAt, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    private var studentsByID: [UUID: CDStudent] {
        Dictionary(
            students.compactMap { s -> (UUID, CDStudent)? in guard let id = s.id else { return nil }; return (id, s) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var lessonsByID: [UUID: CDLesson] {
        Dictionary(
            Array(lessonsRaw).compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var projectSessions: [CDProjectSession] {
        ((club.sessions?.allObjects as? [CDProjectSession]) ?? [])
            .sorted { ($0.meetingDate ?? .distantPast) > ($1.meetingDate ?? .distantPast) }
    }

    private var projectSessionIDs: Set<String> {
        Set(projectSessions.compactMap { $0.id?.uuidString })
    }

    private var projectWorks: [CDWorkModel] {
        Array(allWorkModels).filter { work in
            let isProjectWork = work.sourceContextType == .projectSession || work.sourceContextType == .bookClubSession
            return isProjectWork && projectSessionIDs.contains(work.sourceContextID ?? "")
        }
    }

    private var linkedLessons: [CDLesson] {
        let lessonIDs = Set(projectWorks.compactMap { UUID(uuidString: $0.lessonID) })
        return lessonIDs.compactMap { lessonsByID[$0] }
            .sorted { lhs, rhs in
                if lhs.area == rhs.area { return lhs.name < rhs.name }
                return lhs.area < rhs.area
            }
    }

    private var openFollowUps: [CDWorkModel] {
        projectWorks
            .filter { $0.status != .complete }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var completedWorkCount: Int {
        projectWorks.filter { $0.status == .complete }.count
    }

    private var openQuestions: [ProjectQuestion] {
        projectSessions.flatMap { session in
            session.agendaItems.compactMap { item in
                let trimmed = item.trimmed()
                guard !trimmed.isEmpty else { return nil }
                return ProjectQuestion(session: session, text: trimmed)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                projectHeader
                dashboardMetrics
                lessonConnectionsSection
                studentProgressSection
                followUpsSection
                questionsSection
                sessionsSection
            }
            .padding(AppTheme.Spacing.medium)
        }
        .navigationTitle(club.title)
        .sheet(isPresented: $showNewSession) {
            NewProjectSessionSheet(club: club)
        }
        .sheet(isPresented: $showEditClub) {
            ProjectEditorSheet(club: club)
        }
        .sheet(isPresented: $showManageRoles) {
            NavigationStack { ProjectRolesEditorView(club: club) }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 360)
            #endif
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Label(
                            club.isActive ? "Active Project" : "Completed Project",
                            systemImage: club.isActive ? "sparkle.magnifyingglass" : "checkmark.seal.fill"
                        )
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(club.isActive ? AppColors.info : AppColors.success)
                    }

                    Text(club.title)
                        .font(.largeTitle.weight(.bold))

                    if let seed = club.bookTitle, !seed.isEmpty {
                        Label(seed, systemImage: SFSymbol.Education.bookClosed)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: AppTheme.Spacing.small) {
                    Button {
                        toggleProjectActive()
                    } label: {
                        Label(
                            club.isActive ? "Mark Complete" : "Reopen",
                            systemImage: club.isActive ? "checkmark.circle" : "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showEditClub = true
                    } label: {
                        Label("Edit", systemImage: SFSymbol.Education.pencil)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !club.memberStudentIDsArray.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(club.memberStudentIDsArray, id: \.self) { sid in
                            if let student = studentsByID[uuidString: sid] {
                                ProjectChip(text: StudentFormatter.displayName(for: student), icon: "person.fill")
                            } else {
                                ProjectChip(text: "Unknown", icon: "person.fill.questionmark")
                            }
                        }
                    }
                }
            }
        }
    }

    private var dashboardMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.small)],
            spacing: AppTheme.Spacing.small
        ) {
            ProjectMetricTile(
                title: "Students",
                value: "\(club.memberStudentIDsArray.count)",
                systemImage: SFSymbol.People.person2,
                color: AppColors.info
            )
            ProjectMetricTile(
                title: "Lessons",
                value: "\(linkedLessons.count)",
                systemImage: SFSymbol.Education.bookClosed,
                color: AppColors.success
            )
            ProjectMetricTile(
                title: "Follow-Ups",
                value: "\(openFollowUps.count)",
                systemImage: "arrow.uturn.forward.circle",
                color: AppColors.warning
            )
            ProjectMetricTile(
                title: "Questions",
                value: "\(openQuestions.count)",
                systemImage: "questionmark.bubble",
                color: AppColors.attention
            )
        }
    }

    private var lessonConnectionsSection: some View {
        SectionCard(title: "Lesson Connections", systemImage: SFSymbol.Education.bookClosed) {
            if linkedLessons.isEmpty {
                Text("No lessons linked yet")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: AppTheme.Spacing.small)],
                    spacing: AppTheme.Spacing.small
                ) {
                    ForEach(linkedLessons, id: \.objectID) { lesson in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                            Text(lesson.name)
                                .font(AppTheme.ScaledFont.bodySemibold)
                                .lineLimit(2)
                            Text([lesson.area, lesson.sequence].filter { !$0.isEmpty }.joined(separator: " / "))
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.small)
                        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                        .cornerRadius(UIConstants.CornerRadius.small)
                    }
                }
            }
        }
    }

    private var studentProgressSection: some View {
        SectionCard(title: "Student Progress", systemImage: "person.line.dotted.person") {
            if club.memberStudentIDsArray.isEmpty {
                Text("Add students to begin tracking the project group")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(
                        club.memberStudentIDsArray.sorted { studentName(for: $0) < studentName(for: $1) },
                        id: \.self
                    ) { sid in
                        ProjectStudentProgressRow(
                            studentName: studentName(for: sid),
                            works: workModels(forStudentID: sid)
                        )
                    }
                }
            }
        }
    }

    private var followUpsSection: some View {
        SectionCard(title: "Progress & Follow-Ups", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                if projectWorks.isEmpty {
                    Text("Create a project check-in to start follow-up work")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: Double(completedWorkCount), total: Double(max(projectWorks.count, 1)))
                    Text("\(completedWorkCount) of \(projectWorks.count) follow-ups complete")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    if openFollowUps.isEmpty {
                        Label("All follow-ups are complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                    } else {
                        VStack(spacing: AppTheme.Spacing.xsmall) {
                            ForEach(openFollowUps.prefix(6), id: \.objectID) { work in
                                ProjectFollowUpRow(
                                    work: work,
                                    lesson: UUID(uuidString: work.lessonID).flatMap { lessonsByID[$0] },
                                    studentName: displayStudents(for: work)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var questionsSection: some View {
        SectionCard(title: "Questions & Next Steps", systemImage: "questionmark.bubble") {
            if openQuestions.isEmpty {
                Text("Add student questions and next steps during a check-in")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    ForEach(openQuestions.prefix(8)) { question in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                Text(question.text)
                                    .font(AppTheme.ScaledFont.body)
                                Text(DateFormatters.mediumDate.string(from: question.session.meetingDate ?? Date()))
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var sessionsSection: some View {
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

    private func toggleProjectActive() {
        club.isActive.toggle()
        club.modifiedAt = Date()
        saveCoordinator.save(modelContext, reason: "Update Project Status")
    }

    private func studentName(for sid: String) -> String {
        studentsByID[uuidString: sid].map(StudentFormatter.displayName(for:)) ?? "Student"
    }

    private func workModels(forStudentID sid: String) -> [CDWorkModel] {
        projectWorks.filter { workMatchesStudent($0, studentID: sid) }
    }

    private func workMatchesStudent(_ work: CDWorkModel, studentID: String) -> Bool {
        let participantIDs = work.selectedStudentIDs
        if participantIDs.isEmpty {
            return work.studentID == studentID
        }
        return participantIDs.contains(studentID)
    }

    private func displayStudents(for work: CDWorkModel) -> String {
        let ids = work.selectedStudentIDs.isEmpty ? [work.studentID].filter { !$0.isEmpty } : work.selectedStudentIDs
        let names = ids.map(studentName(for:))
        return names.isEmpty ? "Group" : names.joined(separator: ", ")
    }
}

private struct ProjectQuestion: Identifiable {
    let id = UUID()
    let session: CDProjectSession
    let text: String
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

private struct ProjectMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(UIConstants.OpacityConstants.medium)))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(value)
                    .font(.title2.weight(.bold))
                Text(title)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}

private struct ProjectStudentProgressRow: View {
    let studentName: String
    let works: [CDWorkModel]

    private var completed: Int { works.filter { $0.status == .complete }.count }
    private var reviewing: Int { works.filter { $0.status == .review }.count }
    private var active: Int { works.filter { $0.status == .active }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            HStack {
                Text(studentName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Spacer()
                Text(works.isEmpty ? "No follow-ups" : "\(completed)/\(works.count) complete")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }

            if !works.isEmpty {
                ProgressView(value: Double(completed), total: Double(max(works.count, 1)))
                HStack(spacing: AppTheme.Spacing.small) {
                    ProjectStatusPill(title: "Active", count: active, color: AppColors.info)
                    ProjectStatusPill(title: "Review", count: reviewing, color: AppColors.warning)
                    ProjectStatusPill(title: "Complete", count: completed, color: AppColors.success)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}

private struct ProjectStatusPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(title)")
                .font(AppTheme.ScaledFont.caption)
        }
        .foregroundStyle(.secondary)
    }
}

private struct ProjectFollowUpRow: View {
    @ObservedObject var work: CDWorkModel
    let lesson: CDLesson?
    let studentName: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            Image(systemName: work.status.iconName)
                .foregroundStyle(work.status.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(work.title.isEmpty ? "Untitled follow-up" : work.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Text(studentName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                if let lesson {
                    Text(lesson.name)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = work.dueAt {
                Text(due, format: Date.FormatStyle().month().day())
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, AppTheme.Spacing.xxsmall)

            content
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large + 2, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
}

private struct ProjectChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .padding(.horizontal, AppTheme.Spacing.small + 2)
            .background(
                Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
            )
    }
}
