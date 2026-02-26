import OSLog
import SwiftUI
import SwiftData

struct NewProjectSessionSheet: View {
    private static let logger = Logger.projects
    let club: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var meetingDate: Date = Date()
    @State private var chapterOrPages: String = ""

    @State private var useTemplateWeek: Bool = false
    @State private var selectedTemplateWeekID: UUID?

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

    // Performance: Filter template weeks by projectID at query level
    @Query(sort: [SortDescriptor(\ProjectTemplateWeek.weekIndex, order: .forward)]) private var templateWeeks: [ProjectTemplateWeek]
    // Performance: Filter roles by projectID at query level
    @Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var roles: [ProjectRole]
    @Query private var allLessonAssignments: [LessonAssignment]

    init(club: Project) {
        self.club = club
        // Performance: Filter template weeks by projectID at query level
        let projectIDString = club.id.uuidString
        _templateWeeks = Query(
            filter: #Predicate<ProjectTemplateWeek> { $0.projectID == projectIDString },
            sort: [SortDescriptor(\.weekIndex, order: .forward)]
        )
        // Performance: Filter roles by projectID at query level
        _roles = Query(
            filter: #Predicate<ProjectRole> { $0.projectID == projectIDString },
            sort: [SortDescriptor(\.createdAt, order: .forward)]
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

                Toggle("Use template week", isOn: $useTemplateWeek)
                    .onChange(of: useTemplateWeek) { _, newValue in
                        if newValue, let selectedID = selectedTemplateWeekID,
                           let week = templateWeeks.first(where: { $0.id == selectedID }) {
                            applyTemplateConfig(week)
                        }
                    }

                if useTemplateWeek {
                    Picker("Week", selection: $selectedTemplateWeekID) {
                        ForEach(templateWeeks.sorted { $0.weekIndex < $1.weekIndex }) { w in
                            Text("Week \(w.weekIndex) — \(w.readingRange)").tag(Optional(w.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedTemplateWeekID) { _, newValue in
                        if useTemplateWeek, let selectedID = newValue,
                           let week = templateWeeks.first(where: { $0.id == selectedID }) {
                            applyTemplateConfig(week)
                        }
                    }
                }

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
                            .foregroundStyle(.red)
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
                    .foregroundStyle(.orange)
            }
        }
        .padding(.leading, 8)
    }

    private var isValid: Bool {
        guard !club.memberStudentIDs.isEmpty else { return false }

        // For choice mode, need at least minSelections work offers with titles
        if assignmentMode == .choice {
            let validOffers = offeredWorks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return validOffers.count >= minSelections
        }

        return true
    }

    /// Applies template week configuration to the current session settings
    private func applyTemplateConfig(_ week: ProjectTemplateWeek) {
        chapterOrPages = week.readingRange
        assignmentMode = week.assignmentMode
        minSelections = week.minSelections > 0 ? week.minSelections : 1
        maxSelections = week.maxSelections > 0 ? week.maxSelections : 2
        // Convert template offered works to session work drafts
        offeredWorks = week.offeredWorks.map { templateWork in
            WorkDraft(title: templateWork.title, instructions: templateWork.instructions)
        }
    }

    private func fetchRole(_ id: UUID) -> ProjectRole? {
        return roles.first { $0.id == id }
    }

    private func create() {
        let session = ProjectSession(
            projectID: club.id,
            meetingDate: AppCalendar.startOfDay(meetingDate),
            chapterOrPages: chapterOrPages.isEmpty ? nil : chapterOrPages,
            assignmentMode: assignmentMode,
            minSelections: assignmentMode == .choice ? minSelections : 0,
            maxSelections: assignmentMode == .choice ? maxSelections : 0
        )

        // Populate generic session info
        if useTemplateWeek,
           let selectedID = selectedTemplateWeekID,
           let week = templateWeeks.first(where: { $0.id == selectedID }) {
            session.chapterOrPages = week.readingRange
            session.agendaItems = week.agendaItems
            session.templateWeekID = week.id.uuidString
        }

        // Attach to club immediately so ID is valid
        club.sessions = (club.sessions ?? []) + [session]
        modelContext.insert(session)

        let scheduledDay = AppCalendar.startOfDay(meetingDate)

        // 1. Handle Presentations (Group Inbox) if using template
        if useTemplateWeek,
           let selectedID = selectedTemplateWeekID,
           let week = templateWeeks.first(where: { $0.id == selectedID }) {

            for lessonIDStr in week.linkedLessonIDs {
                guard let lessonID = UUID(uuidString: lessonIDStr) else { continue }
                let memberUUIDs = club.memberStudentIDs.compactMap { UUID(uuidString: $0) }.sorted()
                let existing = allLessonAssignments.first { la in
                    la.lessonIDUUID == lessonID && Set(la.studentUUIDs) == Set(memberUUIDs)
                }

                if let existing {
                    if !existing.isGiven {
                        existing.scheduledFor = scheduledDay
                    }
                } else {
                    let newLA = PresentationFactory.makeScheduled(
                        lessonID: lessonID,
                        studentIDs: memberUUIDs,
                        scheduledFor: scheduledDay
                    )
                    modelContext.insert(newLA)
                }
            }
        }

        // 2. Create Work Items based on assignment mode
        let assignmentService = SessionWorkAssignmentService(context: modelContext)

        switch assignmentMode {
        case .choice:
            // Create offered works (no participants yet)
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
            // Use existing logic for uniform mode (template or generic)
            createUniformWorks(session: session, scheduledDay: scheduledDay)
        }

        _ = saveCoordinator.save(modelContext, reason: "Create Project Session")
        dismiss()
    }

    /// Creates uniform works using existing template/generic logic
    private func createUniformWorks(session: ProjectSession, scheduledDay: Date) {
        let lessonUUID = resolveGenericProjectLessonID(context: modelContext)
        let sharedTemplates = (club.sharedTemplates ?? []).filter { $0.isShared }
        let templateWeek: ProjectTemplateWeek? = (useTemplateWeek && selectedTemplateWeekID != nil) ? templateWeeks.first(where: { $0.id == selectedTemplateWeekID! }) : nil

        for sid in club.memberStudentIDs {
            if let week = templateWeek {
                // Template Mode
                var roleName = "Member"
                if let assignment = week.roleAssignments?.first(where: { $0.studentID == sid }),
                   let roleID = UUID(uuidString: assignment.roleID),
                   let role = fetchRole(roleID) {
                    roleName = role.title
                }

                let title = "\(club.title): Week \(week.weekIndex) (\(roleName))"
                let range = week.readingRange.isEmpty ? "" : "Read: \(week.readingRange)"
                let extras = week.workInstructions.isEmpty ? "" : week.workInstructions

                createWork(
                    studentID: sid,
                    lessonID: lessonUUID,
                    sessionID: session.id,
                    scheduledDate: scheduledDay,
                    title: title,
                    instructions: [range, extras].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )
            } else {
                // Generic Mode
                for tpl in sharedTemplates {
                    createWork(
                        studentID: sid,
                        lessonID: lessonUUID,
                        sessionID: session.id,
                        scheduledDate: scheduledDay,
                        title: tpl.title.isEmpty ? "Shared Assignment" : tpl.title,
                        instructions: tpl.instructions
                    )
                }

                createWork(
                    studentID: sid,
                    lessonID: lessonUUID,
                    sessionID: session.id,
                    scheduledDate: scheduledDay,
                    title: "\(club.title): Individual Work",
                    instructions: "See session notes."
                )
            }
        }
    }
    
    private func createWork(studentID: String, lessonID: UUID, sessionID: UUID, scheduledDate: Date, title: String, instructions: String) {
        // Create WorkModel
        guard let studentUUID = UUID(uuidString: studentID) else { return }
        
        let repository = WorkRepository(context: modelContext)
        do {
            let workModel = try repository.createWork(
                studentID: studentUUID,
                lessonID: lessonID,
                title: title,
                kind: .followUpAssignment,
                presentationID: nil,
                scheduledDate: scheduledDate
            )
            
            // Store session context in notes (WorkModel doesn't have sourceContextType/ID)
            if !instructions.isEmpty {
                Task { @MainActor in
                    _ = workModel.setLegacyNoteText(instructions, in: modelContext)
                }
            }
            
            // Create a WorkCheckIn for scheduled work check-ins
            let checkIn = WorkCheckIn(
                workID: workModel.id,
                date: scheduledDate,
                status: .scheduled,
                purpose: "Due Date",
                note: "",
                work: workModel
            )
            modelContext.insert(checkIn)
            if workModel.checkIns == nil { workModel.checkIns = [] }
            workModel.checkIns = (workModel.checkIns ?? []) + [checkIn]
        } catch {
            Self.logger.warning("Failed to create WorkModel for project session: \(error)")
        }
    }

    private func resolveGenericProjectLessonID(context: ModelContext) -> UUID {
        let name = "Project Work"
        var fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.name == name })
        fetch.fetchLimit = 1
        do {
            let existing = try context.fetch(fetch)
            if let first = existing.first {
                return first.id
            }
        } catch {
            Self.logger.warning("Failed to fetch existing project lesson: \(error)")
        }
        let l = Lesson(name: name, subject: "Projects", group: "Project")
        context.insert(l)
        return l.id
    }
}
