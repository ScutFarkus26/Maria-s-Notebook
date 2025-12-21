import SwiftUI
import SwiftData

// MARK: - Follow-Up Inbox Item
struct FollowUpInboxItem: Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case lessonFollowUp
        case workCheckIn
        case workReview

        var label: String {
            switch self {
            case .lessonFollowUp: return "Lesson"
            case .workCheckIn: return "Check-In"
            case .workReview: return "Review"
            }
        }

        var icon: String {
            switch self {
            case .lessonFollowUp: return "text.book.closed"
            case .workCheckIn: return "checklist"
            case .workReview: return "eye"
            }
        }

        var tint: Color {
            switch self {
            case .lessonFollowUp: return .orange
            case .workCheckIn: return .blue
            case .workReview: return .purple
            }
        }
    }

    enum Bucket: Int, Comparable, CaseIterable {
        case overdue = 0
        case dueToday = 1
        case upcoming = 2

        static func < (lhs: Bucket, rhs: Bucket) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .dueToday: return "Due Today"
            case .upcoming: return "Upcoming"
            }
        }
    }

    // Stable id derived from type + underlying id
    let id: String

    // Underlying references for navigation
    let underlyingID: UUID

    // Display
    let childID: UUID?
    let childName: String
    let title: String
    let kind: Kind
    let statusText: String
    let ageDays: Int
    let bucket: Bucket

    // Sorting composite (bucket, age desc, then childName, then title)
    var sortKey: String {
        let age = String(format: "%04d", ageDays)
        return "\(bucket.rawValue)|\(String(age.reversed()))|\(childName.lowercased())|\(title.lowercased())"
    }
}

// MARK: - Engine
struct FollowUpInboxEngine {
    struct Constants {
        var lessonFollowUpOverdueDays: Int = 7
        var workStaleOverdueDays: Int = 5
        var reviewStaleDays: Int = 3
    }

    static func computeItems(
        lessons: [Lesson],
        students: [Student],
        studentLessons: [StudentLesson],
        contracts: [WorkContract],
        planItems: [WorkPlanItem],
        notes: [ScopedNote],
        modelContext: ModelContext,
        constants: Constants = Constants()
    ) -> [FollowUpInboxItem] {
        var results: [FollowUpInboxItem] = []
        let lessonsByID: [UUID: Lesson] = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let studentsByID: [UUID: Student] = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })

        // Helper: student display name for a set of IDs (single vs group)
        func childName(for ids: [UUID]) -> (UUID?, String) {
            let trimmed = ids
            if trimmed.count == 1, let id = trimmed.first, let s = studentsByID[id] {
                return (id, StudentFormatter.displayName(for: s))
            }
            return (nil, trimmed.isEmpty ? "Student" : "Group")
        }

        // Helper: count school days between two dates (exclusive of today)
        func schoolDaysSince(_ start: Date) -> Int {
            let startDay = AppCalendar.startOfDay(start)
            let today = AppCalendar.startOfDay(Date())
            var count = 0
            var cursor = startDay
            while cursor < today {
                if !SchoolCalendar.isNonSchoolDay(cursor, using: modelContext) { count += 1 }
                cursor = AppCalendar.addingDays(1, to: cursor)
                if count > 36500 { break }
            }
            return max(0, count)
        }

        // Rule 1: Lesson follow-up overdue/upcoming
        do {
            let presented = studentLessons.filter { $0.isPresented || $0.givenAt != nil }

            // Build lookup sets from contracts to exclude lessons with any follow-up work
            let contractsByLegacyStudentLessonID: Set<String> = Set(
                contracts.compactMap { $0.legacyStudentLessonID?.lowercased() }
            )

            // Fallback: childID + lessonID composite (covers manually-created contracts without legacy IDs)
            let contractsByChildLessonKey: Set<String> = Set(
                contracts.compactMap { c in
                    let sid = c.studentID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lid = c.lessonID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !sid.isEmpty, !lid.isEmpty else { return nil }
                    return "\(sid.lowercased())|\(lid.lowercased())"
                }
            )

            for sl in presented {
                let presentedDate = sl.givenAt ?? sl.createdAt
                let days = schoolDaysSince(presentedDate)

                let lessonKey = sl.id.uuidString.lowercased()
                let childLessonKeys: [String] = sl.resolvedStudentIDs.map { sid in
                    "\(sid.uuidString.lowercased())|\(sl.lessonID.uuidString.lowercased())"
                }

                // Exclude if there is any follow-up work linked by legacy ID or by child+lesson fallback.
                let hasFollowUpWork =
                    contractsByLegacyStudentLessonID.contains(lessonKey) ||
                    childLessonKeys.contains(where: { contractsByChildLessonKey.contains($0) })

                guard !hasFollowUpWork else { continue }

                let threshold = constants.lessonFollowUpOverdueDays
                let bucket: FollowUpInboxItem.Bucket
                if days > threshold { bucket = .overdue }
                else if days == threshold { bucket = .dueToday }
                else {
                    let until = max(0, threshold - days)
                    if (1...2).contains(until) { bucket = .upcoming } else { continue }
                }

                let lessonTitle: String = {
                    if let l = lessonsByID[sl.lessonID] {
                        let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty ? "Lesson" : t
                    }
                    return "Lesson"
                }()
                let (cid, cname) = childName(for: sl.resolvedStudentIDs)
                let status: String = {
                    switch bucket {
                    case .overdue: return "Overdue • \(days)d since presented"
                    case .dueToday: return "Due Today • \(days)d since presented"
                    case .upcoming:
                        let until = max(0, threshold - days)
                        return "Due in \(until)d • \(days)d since presented"
                    }
                }()
                let item = FollowUpInboxItem(
                    id: "lessonFollowUp:\(sl.id.uuidString)",
                    underlyingID: sl.id,
                    childID: cid,
                    childName: cname,
                    title: lessonTitle,
                    kind: .lessonFollowUp,
                    statusText: status,
                    ageDays: days,
                    bucket: bucket
                )
                results.append(item)
            }
        }

        // Pre-group planItems and notes for work aging
        let itemsByWorkID: [UUID: [WorkPlanItem]] = Dictionary(grouping: planItems, by: { $0.workID })
        let notesByWorkID: [UUID: [ScopedNote]] = Dictionary(grouping: notes, by: { note in
            if let raw = note.workContractID, let id = UUID(uuidString: raw) { return id }
            return UUID() // unmatched bucket
        })

        // Rule 2/3: Work check-in stale and review stale (with Upcoming)
        for c in contracts {
            let status = c.status
            let isActive = status == .active
            let isReview = status == .review
            guard isActive || isReview else { continue }

            let workItems = itemsByWorkID[c.id] ?? []
            let workNotes = notesByWorkID[c.id] ?? []
            let days = WorkContractAging.daysSinceLastTouch(for: c, modelContext: modelContext, planItems: workItems, notes: workNotes)

            let threshold = isActive ? constants.workStaleOverdueDays : constants.reviewStaleDays
            let bucket: FollowUpInboxItem.Bucket
            if days > threshold { bucket = .overdue }
            else if days == threshold { bucket = .dueToday }
            else {
                let until = max(0, threshold - days)
                if (1...2).contains(until) { bucket = .upcoming } else { continue }
            }

            // Resolve display fields
            let studentName: String = {
                if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
                    return StudentFormatter.displayName(for: s)
                }
                return "Student"
            }()
            let lessonTitle: String = {
                if let lid = UUID(uuidString: c.lessonID), let l = lessonsByID[lid] {
                    let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? "Lesson" : t
                }
                return "Lesson"
            }()
            let (cid, cname): (UUID?, String) = {
                if let sid = UUID(uuidString: c.studentID) { return (sid, studentName) }
                return (nil, studentName)
            }()

            let kind: FollowUpInboxItem.Kind = isActive ? .workCheckIn : .workReview
            let statusText: String = {
                switch bucket {
                case .overdue:
                    return "Overdue • \(days)d since touched"
                case .dueToday:
                    return "Due Today • \(days)d since touched"
                case .upcoming:
                    let until = max(0, threshold - days)
                    return "Due in \(until)d • \(days)d since touched"
                }
            }()

            let item = FollowUpInboxItem(
                id: "\(kind.rawValue):\(c.id.uuidString)",
                underlyingID: c.id,
                childID: cid,
                childName: cname,
                title: lessonTitle,
                kind: kind,
                statusText: statusText,
                ageDays: days,
                bucket: bucket
            )
            results.append(item)
        }

        return results.sorted { lhs, rhs in
            if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
            if lhs.ageDays != rhs.ageDays { return lhs.ageDays > rhs.ageDays }
            if lhs.childName.caseInsensitiveCompare(rhs.childName) != .orderedSame {
                return lhs.childName.localizedCaseInsensitiveCompare(rhs.childName) == .orderedAscending
            }
            if lhs.title.caseInsensitiveCompare(rhs.title) != .orderedSame {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}
