// LessonPlanningService+Helpers.swift
// Plan building, context helpers, and data fetching for LessonPlanningService.

import Foundation
import CoreData

extension LessonPlanningService {

    // MARK: - Week Plan Building

    func buildWeekPlan(
        from recommendations: [LessonRecommendation],
        groupings: [GroupingSuggestion],
        weekStart: Date,
        summary: String
    ) -> WeekPlan {
        let weekDays = (0..<5).compactMap { offset -> (String, Date)? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return (DateFormatters.weekdayAndDate.string(from: date), date)
        }

        var days = weekDays.map { WeekPlan.DayPlanEntry(dayName: $0.0, date: $0.1) }

        // Assign recommendations to days
        for rec in recommendations {
            if let dayName = rec.suggestedDay,
               let dayIndex = days.firstIndex(where: {
                   let prefix = dayName.lowercased().prefix(3)
                   return $0.dayName.lowercased().hasPrefix(String(prefix))
               }) {
                days[dayIndex].recommendations.append(rec)
            } else {
                // Find the day with fewest recommendations
                if let minIndex = days.indices.min(by: {
                    days[$0].recommendations.count < days[$1].recommendations.count
                }) {
                    days[minIndex].recommendations.append(rec)
                }
            }
        }

        return WeekPlan(
            weekStartDate: weekStart,
            days: days,
            groupings: groupings,
            summary: summary
        )
    }

    // MARK: - Context Helpers

    func buildCondensedContext(from session: PlanningSession) -> String {
        var lines: [String] = []

        // Mode description
        switch session.mode {
        case .singleStudent(let id):
            let name = session.readinessProfiles.first { $0.studentID == id }?.studentName ?? "student"
            lines.append("Planning for: \(name)")
        case .wholeClass:
            lines.append("Whole-class weekly planning")
        case .quickSuggest(let ids):
            lines.append("Quick suggestions for \(ids.count) students")
        }

        // Readiness summary (very condensed)
        for profile in session.readinessProfiles.prefix(5) {
            let subjects = profile.subjectReadiness.filter { $0.nextLessonID != nil }.prefix(3)
            let subjectStr = subjects.map { "\($0.subject):\($0.nextLessonName ?? "?")" }.joined(separator: ", ")
            lines.append("\(profile.studentName): \(subjectStr)")
        }

        // Include recent messages (condensed)
        let recentMessages = session.messages.suffix(4)
        for msg in recentMessages {
            let prefix = msg.role == .teacher ? "Teacher" : "Assistant"
            lines.append("\(prefix): \(msg.content.prefix(150))")
        }

        return lines.joined(separator: "\n")
    }

    func encodeRecommendationsForPrompt(_ recs: [LessonRecommendation]) -> String {
        let simplified = recs.map { rec in
            [
                "lessonName": rec.lessonName,
                "subject": rec.subject,
                "group": rec.group,
                "studentNames": rec.studentNames.joined(separator: ", "),
                "reasoning": rec.reasoning,
                "confidence": String(format: "%.2f", rec.confidence),
                "priority": "\(rec.priority)",
                "suggestedDay": rec.suggestedDay ?? ""
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: simplified, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    func buildPreferencesString(subjectFilter: String?, extra: String?) -> String? {
        var parts: [String] = []
        if let subject = subjectFilter {
            parts.append("Focus on \(subject)")
        }
        if let extra {
            parts.append(extra)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    // MARK: - Data Fetching (Core Data)

    func fetchAllLessons() -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "subject", ascending: true),
            NSSortDescriptor(key: "group", ascending: true),
            NSSortDescriptor(key: "orderInGroup", ascending: true)
        ]
        return managedObjectContext.safeFetch(request)
    }

    func fetchAllStudents() -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = [NSSortDescriptor(key: "lastName", ascending: true)]
        return managedObjectContext.safeFetch(request)
    }

    func fetchStudents(for mode: PlanningMode) -> [CDStudent] {
        let allStudents = fetchAllStudents()
        switch mode {
        case .singleStudent(let id):
            return allStudents.filter { $0.id == id }
        case .wholeClass:
            return allStudents
        case .quickSuggest(let ids):
            let idSet = Set(ids)
            return allStudents.filter { guard let sid = $0.id else { return false }; return idSet.contains(sid) }
        }
    }

    func nextWeekStart() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Next Monday
        let daysUntilMonday = (9 - weekday) % 7
        return calendar.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: today) ?? today
    }
}
