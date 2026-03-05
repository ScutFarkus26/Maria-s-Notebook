import Foundation

struct WorkItemDraft: Identifiable {
    let id: UUID
    let studentID: UUID
    var title: String
    var kind: WorkKind
    var status: WorkStatus
    var completionOutcome: CompletionOutcome?
    var completionNote: String
    var checkInDate: Date?
    var dueDate: Date?
    var notes: String
    var showMoreDetails: Bool
    var checkInStyle: CheckInStyle

    init(
        studentID: UUID, title: String = "",
        kind: WorkKind = .practiceLesson,
        status: WorkStatus = .active,
        checkInStyle: CheckInStyle = .flexible
    ) {
        self.id = UUID()
        self.studentID = studentID
        self.title = title
        self.kind = kind
        self.status = status
        self.completionOutcome = nil
        self.completionNote = ""
        self.checkInDate = nil
        self.dueDate = nil
        self.notes = ""
        self.showMoreDetails = false
        self.checkInStyle = checkInStyle
    }
}
