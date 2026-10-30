import SwiftUI
import CoreData

/// Starting a report from a meeting (2026-10-30): its topic, who she's
/// writing it with, and the lesson it comes from. Each child gets a copy,
/// linked to the others, at Topic. It's made at once, not on Complete, so
/// its card shows straight away.
struct StartReportSheet: View {
    let studentID: UUID
    let onDone: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @TestStudentVisibility private var testStudents

    @State private var topic = ""
    @State private var partnerIDs: Set<UUID> = []
    @State private var lessonID: UUID?
    @State private var lessons: [CDLesson] = []

    private var classmates: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled
                .filter { $0.id != studentID }
                .sorted { ($0.firstName, $0.lastName) < ($1.firstName, $1.lastName) },
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        )
    }

    private var canStart: Bool {
        !topic.trimmed().isEmpty && lessonID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    TextField("Topic", text: $topic, prompt: Text("Squishies"))
                }
                Section("From the Lesson") {
                    if lessons.isEmpty {
                        Text("No report lessons yet. Give a lesson a name with “Report” in it, "
                             + "or set the work it makes to Report.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Lesson", selection: $lessonID) {
                            ForEach(lessons, id: \.objectID) { lesson in
                                Text(lesson.name).tag(lesson.id)
                            }
                        }
                    }
                }
                Section("Writing It With") {
                    ForEach(classmates, id: \.objectID) { child in
                        partnerRow(child)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Start a Report")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .disabled(!canStart)
                }
            }
        }
        .task {
            lessons = ReportStages.reportLessons(in: viewContext)
            if lessonID == nil { lessonID = lessons.first?.id }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func partnerRow(_ child: CDStudent) -> some View {
        let isPartner = child.id.map(partnerIDs.contains) ?? false
        return Button {
            guard let id = child.id else { return }
            if isPartner { partnerIDs.remove(id) } else { partnerIDs.insert(id) }
        } label: {
            HStack {
                Text(child.fullName)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isPartner {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPartner ? .isSelected : [])
    }

    private func start() {
        guard let lessonID, canStart else { return }
        // Her copy first, then her partners in the order the list shows them.
        let partners = classmates.compactMap(\.id).filter(partnerIDs.contains)
        let transaction = ContextMutationTransaction(context: viewContext)
        do {
            try ReportStages.startReport(
                title: topic, studentIDs: [studentID] + partners, lessonID: lessonID, context: viewContext
            )
        } catch {
            transaction.rollback()
            ToastService.shared.showError(
                AppErrorMessages.userMessage(for: error, context: "starting the report")
            )
            return
        }
        guard viewContext.safeSave() else {
            transaction.rollback()
            ToastService.shared.showError("Couldn't start the report. Try again.")
            return
        }
        transaction.commit()
        onDone()
    }
}
