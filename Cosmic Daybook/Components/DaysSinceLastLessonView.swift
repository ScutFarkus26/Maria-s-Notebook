import SwiftUI
import CoreData

struct DaysSinceLastLessonView: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext

    /// Computed on appear and when an assignment, a lesson or the day changes,
    /// instead of on every body pass through two live queries (one over every
    /// presented assignment in the store, decoding each one's students).
    @State private var daysSince: Int?

    var body: some View {
        InfoRowView(
            icon: "calendar.badge.clock",
            title: "School Days Since Last Lesson",
            value: daysSince.map { String($0) } ?? "—"
        )
        .onAppear { reload() }
        .onChange(of: student.id) { reload() }
        .onPresentationDataChange(of: ["LessonAssignment", "Lesson"], in: viewContext) { _ in reload() }
        .onCalendarDayChange { reload() }
    }

    private func reload() {
        let fresh: Int? = {
            guard let studentID = student.id,
                  let last = Self.lastLessonDate(studentID: studentID, in: viewContext) else { return nil }
            return LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: viewContext)
        }()
        if fresh != daysSince { daysSince = fresh }
    }

    /// The latest `presentedAt` among presented assignments that include this
    /// student, ignoring parsha lessons.
    ///
    /// Reads newest-first and stops at the first match, which is the maximum
    /// because every row read has a `presentedAt`; rows past the match are
    /// never decoded. (Not batched: a batched fetch's ordering of unsaved rows
    /// is not something to lean on, and the plain fetch sorts them in.)
    static func lastLessonDate(studentID: UUID, in context: NSManagedObjectContext) -> Date? {
        let parshaRequest = CDFetchRequest(CDLesson.self)
        parshaRequest.predicate = NSPredicate(format: "area ==[c] 'parsha' OR sequence ==[c] 'parsha'")
        let excludedLessonIDs = Set(context.safeFetch(parshaRequest).compactMap(\.id))

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "presentedAt != nil")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false),
            NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)
        ]

        let studentIDString = studentID.uuidString
        for la in context.safeFetch(request) {
            guard let presentedAt = la.presentedAt else { continue }
            if la.studentIDs.contains(studentIDString), !excludedLessonIDs.contains(la.resolvedLessonID) {
                return presentedAt
            }
        }
        return nil
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct DaysSinceLastLessonViewPreview: View {
    var body: some View {
        Text("DaysSinceLastLessonView Preview requires app data.")
    }
}

#Preview {
    DaysSinceLastLessonViewPreview()
}
