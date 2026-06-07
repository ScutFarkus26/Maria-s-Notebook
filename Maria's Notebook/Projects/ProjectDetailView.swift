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

    @State var showNewSession: Bool = false
    @State var showEditClub: Bool = false
    @State private var showManageRoles: Bool = false

    init(club: CDProject) {
        self.club = club
        let projectIDString = (club.id ?? UUID()).uuidString
        _roles = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectRole.createdAt, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    var studentsByID: [UUID: CDStudent] {
        Dictionary(
            students.compactMap { s -> (UUID, CDStudent)? in guard let id = s.id else { return nil }; return (id, s) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var lessonsByID: [UUID: CDLesson] {
        Dictionary(
            Array(lessonsRaw).compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var projectSessions: [CDProjectSession] {
        ((club.sessions?.allObjects as? [CDProjectSession]) ?? [])
            .sorted { ($0.meetingDate ?? .distantPast) > ($1.meetingDate ?? .distantPast) }
    }

    var projectSessionIDs: Set<String> {
        Set(projectSessions.compactMap { $0.id?.uuidString })
    }

    var projectWorks: [CDWorkModel] {
        Array(allWorkModels).filter { work in
            let isProjectWork = work.sourceContextType == .projectSession || work.sourceContextType == .bookClubSession
            return isProjectWork && projectSessionIDs.contains(work.sourceContextID ?? "")
        }
    }

    var linkedLessons: [CDLesson] {
        let lessonIDs = Set(projectWorks.compactMap { UUID(uuidString: $0.lessonID) })
        return lessonIDs.compactMap { lessonsByID[$0] }
            .sorted { lhs, rhs in
                if lhs.area == rhs.area { return lhs.name < rhs.name }
                return lhs.area < rhs.area
            }
    }

    var openFollowUps: [CDWorkModel] {
        projectWorks
            .filter { $0.status != .complete }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    var completedWorkCount: Int {
        projectWorks.filter { $0.status == .complete }.count
    }

    var openQuestions: [ProjectQuestion] {
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

    func toggleProjectActive() {
        club.isActive.toggle()
        club.modifiedAt = Date()
        saveCoordinator.save(modelContext, reason: "Update Project Status")
    }

    func studentName(for sid: String) -> String {
        studentsByID[uuidString: sid].map(StudentFormatter.displayName(for:)) ?? "Student"
    }

    func workModels(forStudentID sid: String) -> [CDWorkModel] {
        projectWorks.filter { workMatchesStudent($0, studentID: sid) }
    }

    private func workMatchesStudent(_ work: CDWorkModel, studentID: String) -> Bool {
        let participantIDs = work.selectedStudentIDs
        if participantIDs.isEmpty {
            return work.studentID == studentID
        }
        return participantIDs.contains(studentID)
    }

    func displayStudents(for work: CDWorkModel) -> String {
        let ids = work.selectedStudentIDs.isEmpty ? [work.studentID].filter { !$0.isEmpty } : work.selectedStudentIDs
        let names = ids.map(studentName(for:))
        return names.isEmpty ? "Group" : names.joined(separator: ", ")
    }
}

struct ProjectQuestion: Identifiable {
    let id = UUID()
    let session: CDProjectSession
    let text: String
}
