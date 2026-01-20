import SwiftUI
import SwiftData

struct NewProjectSessionSheet: View {
    let club: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var meetingDate: Date = Date()
    @State private var chapterOrPages: String = ""

    @State private var useTemplateWeek: Bool = false
    @State private var selectedTemplateWeekID: UUID? = nil

    @Query(sort: [SortDescriptor(\ProjectTemplateWeek.weekIndex, order: .forward)]) private var allTemplateWeeks: [ProjectTemplateWeek]
    @Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var allRoles: [ProjectRole]
    @Query private var allStudentLessons: [StudentLesson]

    private var templateWeeks: [ProjectTemplateWeek] {
        allTemplateWeeks.filter { $0.projectID == club.id.uuidString }
    }

    init(club: Project) {
        self.club = club
    }

    var body: some View {
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
                        chapterOrPages = week.readingRange
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
                        chapterOrPages = week.readingRange
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 420)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var isValid: Bool {
        !club.memberStudentIDs.isEmpty
    }
    
    private func fetchRole(_ id: UUID) -> ProjectRole? {
        return allRoles.first { $0.id == id }
    }

    private func create() {
        let session = ProjectSession(
            projectID: club.id,
            meetingDate: AppCalendar.startOfDay(meetingDate),
            chapterOrPages: chapterOrPages.isEmpty ? nil : chapterOrPages
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
                let memberStrings = memberUUIDs.map { $0.uuidString }.sorted()
                
                let lessonIDString = lessonID.uuidString
                let existing = allStudentLessons.first { sl in
                    sl.lessonID == lessonIDString && sl.studentIDs.sorted() == memberStrings
                }
                
                if let existing {
                    if !existing.isGiven {
                        existing.scheduledFor = scheduledDay
                        existing.scheduledForDay = scheduledDay
                    }
                } else {
                    let newSL = StudentLessonFactory.makeScheduled(
                        lessonID: lessonID,
                        studentIDs: memberUUIDs,
                        scheduledFor: scheduledDay
                    )
                    modelContext.insert(newSL)
                }
            }
        }

        // 2. Create Direct Work Items
        // We resolve a generic "Book Club" lesson to attach these work items to.
        let lessonUUID = resolveGenericProjectLessonID(context: modelContext)

        // Prepare data for the work creation loop
        let sharedTemplates = (club.sharedTemplates ?? []).filter { $0.isShared }
        let templateWeek: ProjectTemplateWeek? = (useTemplateWeek && selectedTemplateWeekID != nil) ? templateWeeks.first(where: { $0.id == selectedTemplateWeekID! }) : nil

        for sid in club.memberStudentIDs {
            // A. Determine Content based on Template or Generic
            if let week = templateWeek {
                // -- Template Mode --
                var roleName = "Member"
                if let assignment = week.roleAssignments?.first(where: { $0.studentID == sid }),
                   let roleID = UUID(uuidString: assignment.roleID),
                   let role = fetchRole(roleID) {
                    roleName = role.title
                }
                
                let title = "\(club.title): Week \(week.weekIndex) (\(roleName))"
                let range = week.readingRange.isEmpty ? "" : "Read: \(week.readingRange)"
                let extras = week.workInstructions.isEmpty ? "" : week.workInstructions
                // We'll put instructions in the completion note or just implied by the session
                // For now, we mainly need the WorkModel to exist.
                
                createWork(
                    studentID: sid,
                    lessonID: lessonUUID,
                    sessionID: session.id,
                    scheduledDate: scheduledDay,
                    title: title,
                    instructions: [range, extras].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )

            } else {
                // -- Generic Mode --
                // 1. Create work for shared assignments
                for tpl in sharedTemplates {
                    createWork(
                        studentID: sid,
                        lessonID: lessonUUID, // Or tpl.defaultLinkedLessonID if you prefer specific lessons
                        sessionID: session.id,
                        scheduledDate: scheduledDay,
                        title: tpl.title.isEmpty ? "Shared Assignment" : tpl.title,
                        instructions: tpl.instructions
                    )
                }

                // 2. Create generic individual work
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

        _ = saveCoordinator.save(modelContext, reason: "Create Project Session (Direct Work)")
        dismiss()
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
                workModel.notes = instructions
            }
            
            // Create a WorkCheckIn instead of WorkPlanItem (WorkModel uses checkIns)
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
            #if DEBUG
            print("⚠️ Failed to create WorkModel for project session: \(error)")
            #endif
        }
    }

    private func resolveGenericProjectLessonID(context: ModelContext) -> UUID {
        let name = "Project Work"
        let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.name == name })
        if let existing = try? context.fetch(fetch), let first = existing.first {
            return first.id
        }
        let l = Lesson(name: name, subject: "Projects", group: "Project")
        context.insert(l)
        return l.id
    }
}

