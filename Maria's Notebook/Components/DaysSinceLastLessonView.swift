import SwiftUI
import SwiftData

struct DaysSinceLastLessonView: View {
    let student: Student

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [
        SortDescriptor(\StudentLesson.givenAt, order: .reverse),
        SortDescriptor(\StudentLesson.createdAt, order: .reverse)
    ]) private var allStudentLessons: [StudentLesson]

    @Query private var lessons: [Lesson]

    private var excludedLessonIDs: Set<UUID> {
        func norm(_ s: String) -> String { s.normalizedForComparison() }
        let ids = lessons.filter { l in
            let s = norm(l.subject)
            let g = norm(l.group)
            return s == "parsha" || g == "parsha"
        }.map { $0.id }
        return Set(ids)
    }

    private var lastLessonDate: Date? {
        let relevant = allStudentLessons.filter { sl in
            sl.resolvedStudentIDs.contains(student.id) && sl.isGiven && !excludedLessonIDs.contains(sl.resolvedLessonID)
        }
        var latest: Date? = nil
        for sl in relevant {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
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
        return LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: modelContext, calendar: calendar)
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
