import SwiftUI
import CoreData

struct DaysSinceLastLessonView: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext

    /// Computed on appear and when an assignment, a lesson, the school calendar
    /// or the day changes, instead of on every body pass through two live
    /// queries (one over every presented assignment in the store, decoding each
    /// one's students).
    @State private var daysSince: Int?
    /// Bumped by every change that could move `daysSince`, on screen or not.
    /// The reload follows it only while the row is on screen: a TabView keeps
    /// the Students tab alive behind the others, and `.onAppear` reloads when
    /// it comes back.
    @State private var changeCount = 0

    var body: some View {
        InfoRowView(
            icon: "calendar.badge.clock",
            title: "School Days Since Last Lesson",
            value: daysSince.map { String($0) } ?? "—"
        )
        .onAppear { reload() }
        .onChange(of: student.id) { reload() }
        .onPresentationDataChange(of: ["LessonAssignment", "Lesson"], in: viewContext) { _ in changeCount &+= 1 }
        .onCalendarDayChange { changeCount &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDayDataDidChange)) { _ in
            // AppDependencies drops the shared school-day cache for this same
            // notification, but from a task that can run after this handler;
            // drop it here too, or a synced or restored change would be counted
            // on the old calendar. (A local edit has dropped it already.)
            SchoolCalendarService.shared.invalidateCache()
            changeCount &+= 1
        }
        .onChangeWhenVisible(of: changeCount, catchUpOnAppear: false) { reload() }
    }

    private func reload() {
        let fresh: Int? = {
            guard let studentID = student.id,
                  let last = Self.lastLessonDate(studentID: studentID, in: viewContext) else { return nil }
            return LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: viewContext)
        }()
        if fresh != daysSince { daysSince = fresh }
    }

    /// This child's last given lesson, read the roster's way
    /// (`StudentsViewModel.lastLessonDates`) so the record and the roster's
    /// lesson age never disagree about her (bug hunt 2026-10-17, #44).
    static func lastLessonDate(studentID: UUID, in context: NSManagedObjectContext) -> Date? {
        StudentsViewModel.lastLessonDates(in: context, calendar: AppCalendar.shared)[studentID]
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
