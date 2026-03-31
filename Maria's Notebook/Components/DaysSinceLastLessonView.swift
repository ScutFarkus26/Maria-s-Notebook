import SwiftUI
import CoreData

struct DaysSinceLastLessonView: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false), NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)]) private var allLessonAssignments: FetchedResults<CDLessonAssignment>

    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>

    private var excludedLessonIDs: Set<UUID> {
        func norm(_ s: String) -> String { s.normalizedForComparison() }
        let ids = lessons.filter { l in
            let s = norm(l.subject)
            let g = norm(l.group)
            return s == "parsha" || g == "parsha"
        }.compactMap(\.id)
        return Set(ids)
    }

    private var lastLessonDate: Date? {
        guard let studentID = student.id else { return nil }
        let studentIDString = studentID.uuidString
        let relevant = allLessonAssignments.filter { la in
            la.isPresented
                && la.studentIDs.contains(studentIDString)
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
            title: "School Days Since Last CDLesson",
            value: daysSince.map { String($0) } ?? "—"
        )
    }
}

#Preview {
    Text("DaysSinceLastLessonView Preview requires app data.")
}
