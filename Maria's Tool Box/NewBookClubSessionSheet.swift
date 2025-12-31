import SwiftUI
import SwiftData

struct NewBookClubSessionSheet: View {
    let club: BookClub

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var meetingDate: Date = Date()
    @State private var chapterOrPages: String = ""

    @State private var useTemplateWeek: Bool = false
    @State private var selectedTemplateWeekID: UUID? = nil

    @Query(sort: [SortDescriptor(\BookClubTemplateWeek.weekIndex, order: .forward)]) private var allTemplateWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor(\BookClubRole.createdAt, order: .forward)]) private var allRoles: [BookClubRole]
    @Query private var allStudentLessons: [StudentLesson]

    private var templateWeeks: [BookClubTemplateWeek] {
        allTemplateWeeks.filter { $0.bookClubID == club.id }
    }

    init(club: BookClub) {
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
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var isValid: Bool {
        !club.memberStudentIDs.isEmpty
    }
    
    private func fetchRole(_ id: UUID) -> BookClubRole? {
        return allRoles.first { $0.id == id }
    }

    private func create() {
        let session = BookClubSession(
            bookClubID: club.id,
            meetingDate: AppCalendar.startOfDay(meetingDate),
            chapterOrPages: chapterOrPages.isEmpty ? nil : chapterOrPages
        )
        
        // Populate generic session info
        if useTemplateWeek,
           let selectedID = selectedTemplateWeekID,
           let week = templateWeeks.first(where: { $0.id == selectedID }) {
            session.chapterOrPages = week.readingRange
            session.agendaItems = week.agendaItems
            session.templateWeekID = week.id
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
                
                let existing = allStudentLessons.first { sl in
                    sl.lessonID == lessonID && sl.studentIDs.sorted() == memberUUIDs
                }
                
                if let existing {
                    if !existing.isGiven {
                        existing.scheduledFor = scheduledDay
                        existing.scheduledForDay = scheduledDay
                    }
                } else {
                    let newSL = StudentLesson(
                        lessonID: lessonID,
                        studentIDs: memberUUIDs,
                        scheduledFor: scheduledDay,
                        isPresented: false
                    )
                    modelContext.insert(newSL)
                }
            }
        }

        // 2. Create Direct Work Contracts
        // We resolve a generic "Book Club" lesson to attach these contracts to.
        let lessonUUID = resolveGenericBookClubLessonID(context: modelContext)

        // Prepare data for the contracts loop
        let sharedTemplates = (club.sharedTemplates ?? []).filter { $0.isShared }
        let templateWeek: BookClubTemplateWeek? = (useTemplateWeek && selectedTemplateWeekID != nil) ? templateWeeks.first(where: { $0.id == selectedTemplateWeekID! }) : nil

        for sid in club.memberStudentIDs {
            // A. Determine Content based on Template or Generic
            if let week = templateWeek {
                // -- Template Mode --
                var roleName = "Member"
                if let assignment = week.roleAssignments?.first(where: { $0.studentID == sid }),
                   let role = fetchRole(assignment.roleID) {
                    roleName = role.title
                }
                
                let title = "\(club.title): Week \(week.weekIndex) (\(roleName))"
                let range = week.readingRange.isEmpty ? "" : "Read: \(week.readingRange)"
                let extras = week.workInstructions.isEmpty ? "" : week.workInstructions
                // We'll put instructions in the completion note or just implied by the session
                // For now, we mainly need the WorkContract to exist.
                
                createContract(
                    studentID: sid,
                    lessonID: lessonUUID,
                    sessionID: session.id,
                    scheduledDate: scheduledDay,
                    title: title,
                    instructions: [range, extras].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )
                
            } else {
                // -- Generic Mode --
                // 1. Create contracts for shared assignments
                for tpl in sharedTemplates {
                    createContract(
                        studentID: sid,
                        lessonID: lessonUUID, // Or tpl.defaultLinkedLessonID if you prefer specific lessons
                        sessionID: session.id,
                        scheduledDate: scheduledDay,
                        title: tpl.title.isEmpty ? "Shared Assignment" : tpl.title,
                        instructions: tpl.instructions
                    )
                }
                
                // 2. Create generic individual contract
                createContract(
                    studentID: sid,
                    lessonID: lessonUUID,
                    sessionID: session.id,
                    scheduledDate: scheduledDay,
                    title: "\(club.title): Individual Work",
                    instructions: "See session notes."
                )
            }
        }

        _ = saveCoordinator.save(modelContext, reason: "Create Book Club Session (Direct Work)")
        dismiss()
    }
    
    private func createContract(studentID: String, lessonID: UUID, sessionID: UUID, scheduledDate: Date, title: String, instructions: String) {
        let contract = WorkContract(
            studentID: studentID,
            lessonID: lessonID.uuidString,
            presentationID: nil,
            status: .active,
            scheduledDate: scheduledDate,
            completedAt: nil
        )
        contract.sourceContextType = .bookClubSession
        contract.sourceContextID = sessionID.uuidString
        contract.kind = .followUpAssignment
        
        // Store the "Title" (Role info) in scheduledNote so it appears in lists
        contract.scheduledNote = title
        
        // Note: 'instructions' could be added to a note if WorkContract supported a description field,
        // or we can insert a ScopedNote if really needed. For now, we rely on the session context.
        
        modelContext.insert(contract)
        
        // Create a WorkPlanItem (Due Date)
        let planItem = WorkPlanItem(workID: contract.id, scheduledDate: scheduledDate, reason: .dueDate, note: nil)
        modelContext.insert(planItem)
    }

    private func resolveGenericBookClubLessonID(context: ModelContext) -> UUID {
        let name = "Book Club Work"
        let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.name == name })
        if let existing = try? context.fetch(fetch), let first = existing.first {
            return first.id
        }
        let l = Lesson(name: name, subject: "Book Clubs", group: "Book Club")
        context.insert(l)
        return l.id
    }
}

