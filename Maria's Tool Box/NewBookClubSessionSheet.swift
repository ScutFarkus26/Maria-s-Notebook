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
    @Query(sort: [SortDescriptor(\BookClubChoiceItem.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor(\BookClubRole.createdAt, order: .forward)]) private var allRoles: [BookClubRole]

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
        !club.memberStudentIDs.isEmpty && club.sharedTemplates.filter { $0.isShared }.count >= 2
    }

    private func questionsSummary(for week: BookClubTemplateWeek) -> String {
        guard let setID = week.questionChoiceSetID else { return "" }
        let items = allChoiceItems.filter { $0.setID == setID }
        let titles = items.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return titles.isEmpty ? "" : titles.joined(separator: "; ")
    }

    private func linkedLessonIDForWeeklyQuestions(of week: BookClubTemplateWeek) -> String? {
        guard let setID = week.questionChoiceSetID else { return nil }
        // Collect linked lesson IDs from the choice items in this set
        let linkedIDs: [String] = allChoiceItems
            .filter { $0.setID == setID }
            .compactMap { $0.linkedLessonID?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // If there is exactly one unique linked lesson, use it; otherwise leave nil (ambiguous or none)
        let unique = Array(Set(linkedIDs))
        return unique.count == 1 ? unique.first : nil
    }

    private func fetchRole(_ id: UUID) -> BookClubRole? {
        return allRoles.first { $0.id == id }
    }

    private func mapStatus(_ s: BookClubDeliverableStatus) -> WorkStatus {
        switch s {
        case .assigned, .inProgress:
            return .active
        case .readyForReview:
            return .review
        case .completed:
            return .complete
        }
    }

    private func lessonIDForDeliverableTitle(_ title: String, instructions: String) -> UUID {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lessonName = trimmed.isEmpty ? "Book Club Work" : "Book Club: \(trimmed)"
        // Try to find an existing lesson with this name in the Book Clubs subject/group
        let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.name == lessonName && $0.subject == "Book Clubs" && $0.group == "Book Club" })
        if let existing = try? modelContext.fetch(fetch), let first = existing.first {
            return first.id
        }
        // Create a new generic lesson
        let lesson = Lesson(
            name: lessonName,
            subject: "Book Clubs",
            group: "Book Club",
            subheading: "",
            writeUp: instructions
        )
        modelContext.insert(lesson)
        return lesson.id
    }

    private func create() {
        let session = BookClubSession(
            bookClubID: club.id,
            meetingDate: AppCalendar.startOfDay(meetingDate),
            chapterOrPages: chapterOrPages.isEmpty ? nil : chapterOrPages
        )

        if useTemplateWeek,
           let selectedID = selectedTemplateWeekID,
           let week = templateWeeks.first(where: { $0.id == selectedID }) {
            // Use template week data
            session.chapterOrPages = week.readingRange
            session.agendaItems = week.agendaItems
            session.templateWeekID = week.id

            for sid in club.memberStudentIDs {
                // Weekly Questions deliverable
                let questionsInstructions = questionsSummary(for: week)
                let weeklyQuestions = BookClubDeliverable(
                    sessionID: session.id,
                    studentID: sid,
                    templateID: nil,
                    title: "Weekly Questions",
                    instructions: questionsInstructions,
                    status: .assigned,
                    linkedLessonID: linkedLessonIDForWeeklyQuestions(of: week),
                    sourceContextID: session.id,
                    templateWeekID: week.id,
                    choiceSetID: week.questionChoiceSetID
                )
                session.deliverables.append(weeklyQuestions)

                // Vocabulary deliverable
                let vocabInstr = "Choose \(week.vocabRequirementCount) words from: \(week.vocabSuggestionWords.joined(separator: ", "))"
                let vocabulary = BookClubDeliverable(
                    sessionID: session.id,
                    studentID: sid,
                    templateID: nil,
                    title: "Vocabulary (\(week.vocabRequirementCount))",
                    instructions: vocabInstr,
                    status: .assigned,
                    sourceContextID: session.id,
                    templateWeekID: week.id
                )
                session.deliverables.append(vocabulary)

                // Weekly Job deliverable
                if let roleAssignment = week.roleAssignments.first(where: { $0.studentID == sid }),
                   let role = fetchRole(roleAssignment.roleID) {
                    let weeklyJob = BookClubDeliverable(
                        sessionID: session.id,
                        studentID: sid,
                        templateID: nil,
                        title: role.title,
                        instructions: role.instructions,
                        status: .assigned,
                        sourceContextID: session.id,
                        templateWeekID: week.id
                    )
                    session.deliverables.append(weeklyJob)
                }
            }
        } else {
            // Existing creation logic
            let shared = club.sharedTemplates.filter { $0.isShared }
            for sid in club.memberStudentIDs {
                for tpl in shared { // shared templates
                    let d = BookClubDeliverable(
                        sessionID: session.id,
                        studentID: sid,
                        templateID: tpl.id,
                        title: tpl.title.isEmpty ? "Shared Assignment" : tpl.title,
                        instructions: tpl.instructions,
                        status: .assigned,
                        linkedLessonID: tpl.defaultLinkedLessonID
                    )
                    session.deliverables.append(d)
                }
                // Individual assignment
                let individual = BookClubDeliverable(
                    sessionID: session.id,
                    studentID: sid,
                    templateID: nil,
                    title: "Individual Assignment",
                    instructions: "",
                    status: .assigned
                )
                session.deliverables.append(individual)
            }
        }

        // Auto-generate WorkContracts for all deliverables and schedule them for the session date
        let scheduledDay = AppCalendar.startOfDay(meetingDate)
        for d in session.deliverables {
            // Resolve or create a lesson ID for this deliverable
            var lessonUUID: UUID?
            if let lid = d.linkedLessonID, let uuid = UUID(uuidString: lid) {
                lessonUUID = uuid
            } else {
                let newID = lessonIDForDeliverableTitle(d.title, instructions: d.instructions)
                lessonUUID = newID
                d.linkedLessonID = newID.uuidString
            }
            guard let lessonUUID else { continue }

            // Map deliverable status to WorkStatus
            let initialStatus = mapStatus(d.status)

            // Create the WorkContract
            let contract = WorkContract(
                studentID: d.studentID,
                lessonID: lessonUUID.uuidString,
                presentationID: nil,
                status: initialStatus,
                scheduledDate: scheduledDay,
                completedAt: nil,
                legacyStudentLessonID: nil
            )
            // Tag as Book Club source and set kind to follow-up
            contract.sourceContextType = .bookClubSession
            contract.sourceContextID = session.id.uuidString
            contract.kind = .followUpAssignment

            modelContext.insert(contract)
            d.generatedWorkID = contract.id

            // Create a WorkPlanItem scheduled for the session date (mark as Due)
            let planItem = WorkPlanItem(workID: contract.id, scheduledDate: scheduledDay, reason: .dueDate, note: nil)
            modelContext.insert(planItem)
        }

        // Attach to club
        let updatedClub = club
        updatedClub.sessions.append(session)

        modelContext.insert(session)
        for d in session.deliverables { modelContext.insert(d) }

        _ = saveCoordinator.save(modelContext, reason: "Create Book Club Session")
        dismiss()
    }
}

