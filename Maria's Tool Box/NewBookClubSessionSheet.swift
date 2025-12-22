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

    private func fetchRole(_ id: UUID) -> BookClubRole? {
        return allRoles.first { $0.id == id }
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

        // Attach to club
        let updatedClub = club
        updatedClub.sessions.append(session)

        modelContext.insert(session)
        for d in session.deliverables { modelContext.insert(d) }

        _ = saveCoordinator.save(modelContext, reason: "Create Book Club Session")
        dismiss()
    }
}

