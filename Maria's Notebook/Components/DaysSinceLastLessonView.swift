import SwiftUI
import CoreData

struct DaysSinceLastLessonView: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    // Only fetch presented assignments — eliminates all scheduled/draft rows from the scan.
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false),
            NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)
        ],
        predicate: NSPredicate(format: "presentedAt != nil")
    ) private var presentedAssignments: FetchedResults<CDLessonAssignment>

    // Only fetch lessons that belong to the excluded "parsha" area/sequence,
    // instead of loading the entire lesson library just to build the exclusion set.
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "area ==[c] 'parsha' OR sequence ==[c] 'parsha'")
    ) private var parshaLessons: FetchedResults<CDLesson>

    private var excludedLessonIDs: Set<UUID> {
        Set(parshaLessons.compactMap(\.id))
    }

    private var lastLessonDate: Date? {
        guard let studentID = student.id else { return nil }
        let studentIDString = studentID.uuidString
        // presentedAssignments already has presentedAt != nil, so no isPresented check needed.
        let relevant = presentedAssignments.filter { la in
            la.studentIDs.contains(studentIDString)
                && !excludedLessonIDs.contains(la.resolvedLessonID)
        }
        var latest: Date?
        for la in relevant {
            guard let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt else { continue }
            if let cur = latest {
                if when > cur { latest = when }
            } else {
                latest = when
            }
        }
        return latest
    }

    private var daysSince: Int? {
        guard let last = lastLessonDate else { return nil }
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: last, asOf: Date(), using: viewContext, calendar: calendar
        )
    }

    var body: some View {
        InfoRowView(
            icon: "calendar.badge.clock",
            title: "School Days Since Last Lesson",
            value: daysSince.map { String($0) } ?? "—"
        )
    }
}

#Preview {
    Text("DaysSinceLastLessonView Preview requires app data.")
}
