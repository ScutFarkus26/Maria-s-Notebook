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
        case inbox = 2
        case upcoming = 3

        static func < (lhs: Bucket, rhs: Bucket) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .dueToday: return "Due Today"
            case .inbox: return "Needs Scheduling"
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
        // Migration flag: choose work source internally
        if WorkMigrationFlags.useWorkModelInInbox {
            // TODO: WorkModel path will be implemented in PROMPT 5
            // For now, fall through to WorkContract path to preserve behavior
        }
        
        // Default path: use WorkContract (existing behavior)
        return computeItemsFromContracts(
            lessons: lessons,
            students: students,
            studentLessons: studentLessons,
            contracts: contracts,
            planItems: planItems,
            notes: notes,
            modelContext: modelContext,
            constants: constants
        )
    }
    
    /// Internal helper: compute items from WorkContract (existing implementation)
    private static func computeItemsFromContracts(
        lessons: [Lesson],
        students: [Student],
        studentLessons: [StudentLesson],
        contracts: [WorkContract],
        planItems: [WorkPlanItem],
        notes: [ScopedNote],
        modelContext: ModelContext,
        constants: Constants
    ) -> [FollowUpInboxItem] {
        var results: [FollowUpInboxItem] = []
        let lessonsByID: [UUID: Lesson] = lessons.toDictionary(by: \.id)
        let studentsByID: [UUID: Student] = students.toDictionary(by: \.id)

        // Helper: student display name for a set of IDs (single vs group)
        func childName(for ids: [UUID]) -> (UUID?, String) {
            let trimmed = ids
            if trimmed.count == 1, let id = trimmed.first, let s = studentsByID[id] {
                return (id, StudentFormatter.displayName(for: s))
            }
            return (nil, trimmed.isEmpty ? "Student" : "Group")
        }

        // Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches
        func isNonSchoolDaySync(_ date: Date) -> Bool {
            let day = AppCalendar.startOfDay(date)

            // 1) Explicit non-school day wins
            do {
                let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
                let nonSchoolDays: [NonSchoolDay] = try modelContext.fetch(nsDescriptor)
                if !nonSchoolDays.isEmpty { return true }
            } catch {
                // On fetch error, fall back to weekend logic below
            }

            // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
            let cal = AppCalendar.shared
            let weekday = cal.component(.weekday, from: day)
            let isWeekend = (weekday == 1 || weekday == 7)
            guard isWeekend else { return false }

            // 3) Weekend override makes it a school day
            do {
                let ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
                let overrides: [SchoolDayOverride] = try modelContext.fetch(ovDescriptor)
                if !overrides.isEmpty { return false }
            } catch {
                // If override fetch fails, assume weekend remains non-school
            }
            return true
        }

        // Helper: count school days between two dates (exclusive of today)
        func schoolDaysSince(_ start: Date) -> Int {
            let startDay = AppCalendar.startOfDay(start)
            let today = AppCalendar.startOfDay(Date())
            var count = 0
            var cursor = startDay
            while cursor < today {
                if !isNonSchoolDaySync(cursor) { count += 1 }
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
                // CloudKit compatibility: lessonID is already String
                let childLessonKeys: [String] = sl.resolvedStudentIDs.map { sid in
                    "\(sid.uuidString.lowercased())|\(sl.lessonID.lowercased())"
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
                    if let lessonUUID = UUID(uuidString: sl.lessonID), let l = lessonsByID[lessonUUID] {
                        return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
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
                    case .inbox:
                        return "Needs scheduling • \(days)d since presented"
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
        let itemsByWorkID: [UUID: [WorkPlanItem]] = planItems.grouped { UUID(uuidString: $0.workID) ?? UUID() }
        let notesByWorkID: [UUID: [ScopedNote]] = notes.grouped { note in
            note.workContractID.flatMap(UUID.init(uuidString:)) ?? UUID()
        }

        var addedContractIDs: Set<UUID> = []

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
                    return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
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
                case .inbox:
                    return "Needs scheduling • \(days)d since touched"
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
            addedContractIDs.insert(c.id)
        }

        // Rule 4: Unscheduled open work (needs scheduling inbox)
        for c in contracts {
            let status = c.status
            let isActive = status == .active
            let isReview = status == .review
            guard isActive || isReview else { continue }
            // Skip if already added by Rule 2/3
            guard !addedContractIDs.contains(c.id) else { continue }
            // Only include when there are no plan items and no scheduledDate
            let workItems = itemsByWorkID[c.id] ?? []
            guard workItems.isEmpty && c.scheduledDate == nil else { continue }

            // Display fields
            let studentName: String = {
                if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
                    return StudentFormatter.displayName(for: s)
                }
                return "Student"
            }()
            let lessonTitle: String = {
                if let lid = UUID(uuidString: c.lessonID), let l = lessonsByID[lid] {
                    return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
                }
                return "Lesson"
            }()
            let (cid, cname): (UUID?, String) = {
                if let sid = UUID(uuidString: c.studentID) { return (sid, studentName) }
                return (nil, studentName)
            }()

            // Age for secondary text
            let days = WorkContractAging.daysSinceLastTouch(for: c, modelContext: modelContext, planItems: workItems, notes: [])
            let statusText = "Needs scheduling • \(days)d since touched"

            let kind: FollowUpInboxItem.Kind = isActive ? .workCheckIn : .workReview
            let item = FollowUpInboxItem(
                id: "inbox:\(c.id.uuidString)",
                underlyingID: c.id,
                childID: cid,
                childName: cname,
                title: lessonTitle,
                kind: kind,
                statusText: statusText,
                ageDays: days,
                bucket: .inbox
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
