import SwiftUI
import SwiftData

struct NewBookClubSessionSheet: View {
    let club: BookClub

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var meetingDate: Date = Date()
    @State private var chapterOrPages: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Session")
                .font(.title2).fontWeight(.semibold)

            DatePicker("Meeting Date", selection: $meetingDate, displayedComponents: .date)
            TextField("Chapter/Pages (optional)", text: $chapterOrPages)
                .textFieldStyle(.roundedBorder)

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

    private func create() {
        let session = BookClubSession(bookClubID: club.id, meetingDate: AppCalendar.startOfDay(meetingDate), chapterOrPages: chapterOrPages.isEmpty ? nil : chapterOrPages)

        // Generate deliverables: 2 shared + 1 individual per student
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

        // Attach to club
        var updatedClub = club
        updatedClub.sessions.append(session)

        modelContext.insert(session)
        for d in session.deliverables { modelContext.insert(d) }

        _ = saveCoordinator.save(modelContext, reason: "Create Book Club Session")
        dismiss()
    }
}
