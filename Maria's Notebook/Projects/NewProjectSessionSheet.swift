// swiftlint:disable file_length
import OSLog
import SwiftUI
import CoreData

// swiftlint:disable:next type_body_length
struct NewProjectSessionSheet: View {
    private static let logger = Logger.projects
    let club: CDProject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var meetingDate: Date = Date()
    @State private var chapterOrPages: String = ""

    // Assignment mode state
    @State private var assignmentMode: SessionAssignmentMode = .uniform
    @State private var minSelections: Int = 1
    @State private var maxSelections: Int = 2

    // Offered works for choice mode
    @State private var offeredWorks: [WorkDraft] = []

    struct WorkDraft: Identifiable {
        let id = UUID()
        var title: String = ""
        var instructions: String = ""

        init(title: String = "", instructions: String = "") {
            self.title = title
            self.instructions = instructions
        }
    }

    // Performance: Filter roles by projectID at query level
    @FetchRequest private var roles: FetchedResults<CDProjectRole>

    init(club: CDProject) {
        self.club = club
        let projectIDString = (club.id ?? UUID()).uuidString
        _roles = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectRole.createdAt, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Session")
                    .font(.title2).fontWeight(.semibold)

                DatePicker("Meeting Date", selection: $meetingDate, displayedComponents: .date)
                TextField("Chapter/Pages (optional)", text: $chapterOrPages)
                    .textFieldStyle(.roundedBorder)

                Divider()

                // Assignment Mode Section
                assignmentModeSection

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Create") { create() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
            .padding(16)
        }
    #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    // MARK: - Assignment Mode Section

    @ViewBuilder
    private var assignmentModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assignment Mode")
                .font(.headline)

            Picker("Mode", selection: $assignmentMode) {
                ForEach(SessionAssignmentMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(assignmentMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if assignmentMode == .choice {
                choiceModeConfiguration
            }
        }
    }

    @ViewBuilder
    private var choiceModeConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Students pick")
                Stepper("\(minSelections)", value: $minSelections, in: 1...10)
                    .fixedSize()
                Text("of")
                Stepper("\(maxSelections == 0 ? "∞" : "\(maxSelections)")", value: $maxSelections, in: 0...10)
                    .fixedSize()
            }
            .font(.subheadline)

            Divider()

            Text("Offered Works")
                .font(.subheadline).fontWeight(.medium)

            ForEach($offeredWorks) { $work in
                HStack(alignment: .top) {
                    VStack(spacing: 4) {
                        TextField("Title", text: $work.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Instructions (optional)", text: $work.instructions)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    Button {
                        offeredWorks.removeAll { $0.id == work.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                offeredWorks.append(WorkDraft())
            } label: {
                Label("Add Work Offer", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)

            if offeredWorks.count < minSelections {
                Text("Add at least \(minSelections) work offers")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.leading, 8)
    }

    private var isValid: Bool {
        guard !club.memberStudentIDsArray.isEmpty else { return false }

        if assignmentMode == .choice {
            let validOffers = offeredWorks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return validOffers.count >= minSelections
        }

        return true
    }

    private func create() {
        let session = CDProjectSession(context: managedObjectContext)
        session.projectID = club.id?.uuidString ?? ""
        session.meetingDate = AppCalendar.startOfDay(meetingDate)
        session.chapterOrPages = chapterOrPages.isEmpty ? nil : chapterOrPages
        session.assignmentMode = assignmentMode
        session.minSelections = assignmentMode == .choice ? Int64(minSelections) : 0
        session.maxSelections = assignmentMode == .choice ? Int64(maxSelections) : 0

        // Attach to club immediately so ID is valid
        club.addToSessions(session)

        let scheduledDay = AppCalendar.startOfDay(meetingDate)

        // Create Work Items based on assignment mode
        let assignmentService = SessionWorkAssignmentService(context: managedObjectContext)

        switch assignmentMode {
        case .choice:
            for draft in offeredWorks where !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    try assignmentService.createOfferedWork(
                        session: session,
                        title: draft.title,
                        instructions: draft.instructions,
                        dueDate: scheduledDay
                    )
                } catch {
                    Self.logger.warning("Failed to create offered work: \(error)")
                }
            }

        case .uniform:
            createUniformWorks(session: session, scheduledDay: scheduledDay)
        }

        saveCoordinator.save(managedObjectContext, reason: "Create Project Session")
        dismiss()
    }

    /// Creates uniform works for all members
    private func createUniformWorks(session: CDProjectSession, scheduledDay: Date) {
        let lessonUUID = resolveGenericProjectLessonID(context: managedObjectContext)

        for sid in club.memberStudentIDsArray {
            createWork(
                studentID: sid,
                lessonID: lessonUUID,
                sessionID: session.id ?? UUID(),
                scheduledDate: scheduledDay,
                title: "\(club.title): Individual Work",
                instructions: "See session notes."
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func createWork(
        studentID: String,
        lessonID: UUID,
        sessionID: UUID,
        scheduledDate: Date,
        title: String,
        instructions: String
    ) {
        guard let studentUUID = UUID(uuidString: studentID) else { return }

        let repository = WorkRepository(context: managedObjectContext)
        do {
            let workModel = try repository.createWork(
                studentID: studentUUID,
                lessonID: lessonID,
                title: title,
                kind: .followUpAssignment,
                presentationID: nil,
                scheduledDate: scheduledDate
            )

            if !instructions.isEmpty {
                workModel.setLegacyNoteText(instructions, in: managedObjectContext)
            }

            let checkInService = WorkCheckInService(context: managedObjectContext)
            try checkInService.createCheckIn(
                for: workModel,
                date: scheduledDate,
                status: .scheduled,
                purpose: "Due Date",
                note: ""
            )
        } catch {
            Self.logger.warning("Failed to create CDWorkModel for project session: \(error)")
        }
    }

    private func resolveGenericProjectLessonID(context: NSManagedObjectContext) -> UUID {
        let name = "Project Work"
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "name == %@", name)
        request.fetchLimit = 1
        let existing = context.safeFetch(request)
        if let first = existing.first, let firstID = first.id {
            return firstID
        }
        let l = CDLesson(context: context)
        l.id = UUID()
        l.name = name
        l.subject = "Projects"
        l.group = "Project"
        return l.id!
    }
}
