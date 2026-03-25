import SwiftUI
import SwiftData

struct DaysSinceLastLessonView: View {
    let student: Student

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [
        SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
        SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
    ]) private var allLessonAssignments: [LessonAssignment]

    @Query private var lessons: [Lesson]

    private var excludedLessonIDs: Set<UUID> {
        func norm(_ s: String) -> String { s.normalizedForComparison() }
        let ids = lessons.filter { l in
            let s = norm(l.subject)
            let g = norm(l.group)
            return s == "parsha" || g == "parsha"
        }.map(\.id)
        return Set(ids)
    }

    private var lastLessonDate: Date? {
        let studentIDString = student.id.uuidString
        let relevant = allLessonAssignments.filter { la in
            la.isPresented
                && la.studentIDs.contains(studentIDString)
                && !excludedLessonIDs.contains(la.resolvedLessonID)
        }
        var latest: Date?
        for la in relevant {
            let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt
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
            createdAt: last, asOf: Date(), using: modelContext, calendar: calendar
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
