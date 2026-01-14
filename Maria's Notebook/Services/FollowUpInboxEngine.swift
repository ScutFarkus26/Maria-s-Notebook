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
        contracts: [WorkContract] = [],
        planItems: [WorkPlanItem] = [],
        notes: [Note] = [],
        modelContext: ModelContext,
        constants: Constants = Constants()
    ) -> [FollowUpInboxItem] {
        // Always use WorkModel as the primary source of truth
        // Legacy WorkContract arrays are ignored; engine fetches WorkModel internally
        return computeItemsFromWorkModels(
            lessons: lessons,
            students: students,
            studentLessons: studentLessons,
            modelContext: modelContext,
            constants: constants
        )
    }
    
    #if DEBUG
    /// Debug-only helper to compare results from two paths
    private static func compareResults(newPath: [FollowUpInboxItem], legacyPath: [FollowUpInboxItem], pathName: String) {
        let newByBucket = Dictionary(grouping: newPath, by: { $0.bucket })
        let legacyByBucket = Dictionary(grouping: legacyPath, by: { $0.bucket })
        
        var differences: [String] = []
        
        for bucket in FollowUpInboxItem.Bucket.allCases {
            let newCount = newByBucket[bucket]?.count ?? 0
            let legacyCount = legacyByBucket[bucket]?.count ?? 0
            if newCount != legacyCount {
                differences.append("\(bucket.title): new=\(newCount) legacy=\(legacyCount)")
            }
        }
        
        if !differences.isEmpty {
            print("⚠️ FollowUpInboxEngine parity check (\(pathName)): \(differences.joined(separator: ", "))")
        } else {
            print("✅ FollowUpInboxEngine parity check (\(pathName)): All bucket counts match")
        }
    }
    #endif
    
    /// Compute items scoped to a specific student.
    /// This is used by the student checklist tab to get work items for that student.
    static func computeItems(
        for studentID: UUID,
        lessons: [Lesson],
        students: [Student],
        studentLessons: [StudentLesson],
        contracts: [WorkContract] = [],
        planItems: [WorkPlanItem] = [],
        notes: [Note] = [],
        modelContext: ModelContext,
        constants: Constants = Constants()
    ) -> [FollowUpInboxItem] {
        // Get all items and filter by student
        // Legacy contracts/planItems/notes parameters are ignored; engine fetches WorkModel internally
        let allItems = computeItems(
            lessons: lessons,
            students: students,
            studentLessons: studentLessons,
            modelContext: modelContext,
            constants: constants
        )
        
        // Filter to items for this student
        return allItems.filter { item in
            item.childID == studentID
        }
    }
    
    /// Internal helper: compute items from WorkContract (legacy path)
    private static func computeItemsFromContracts(
        lessons: [Lesson],
        students: [Student],
        studentLessons: [StudentLesson],
        contracts: [WorkContract],
        planItems: [WorkPlanItem],
        notes: [Note],
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
        let notesByWorkID: [UUID: [Note]] = notes.grouped { note in
            note.workContract?.id ?? UUID()
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
    
    /// Internal helper: compute items from WorkModel (migration path)
    private static func computeItemsFromWorkModels(
        lessons: [Lesson],
        students: [Student],
        studentLessons: [StudentLesson],
        modelContext: ModelContext,
        constants: Constants
    ) -> [FollowUpInboxItem] {
        var results: [FollowUpInboxItem] = []
        let lessonsByID: [UUID: Lesson] = lessons.toDictionary(by: \.id)
        let studentsByID: [UUID: Student] = students.toDictionary(by: \.id)
        
        // Fetch open WorkModel records once per compute (cached per refresh scope)
        #if DEBUG
        let workModelFetchStart = Date()
        var workModelFetchCount = 0
        #endif
        
        let completeRaw = WorkStatus.complete.rawValue
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.statusRaw != completeRaw
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        #if DEBUG
        workModelFetchCount += 1
        #endif
        let allWorkModels = (try? modelContext.fetch(descriptor)) ?? []
        let openWorkModels = allWorkModels.filter { $0.isOpen && $0.status != .complete }
        
        #if DEBUG
        let workModelFetchDuration = Date().timeIntervalSince(workModelFetchStart)
        print("📊 FollowUpInboxEngine: Fetched \(allWorkModels.count) WorkModels (\(openWorkModels.count) open) in \(String(format: "%.3f", workModelFetchDuration))s (fetch count: \(workModelFetchCount))")
        assert(workModelFetchCount == 1, "⚠️ FollowUpInboxEngine: Expected 1 WorkModel fetch, got \(workModelFetchCount)")
        #endif
        
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
            
            // Build lookup sets from WorkModels to exclude lessons with any follow-up work
            // Check by studentLessonID
            let workModelsByStudentLessonID: Set<UUID> = Set(
                openWorkModels.compactMap { $0.studentLessonID }
            )
            
            // Also check by participant studentID + lessonID (via studentLesson lookup)
            let workModelsByStudentLessonKey: Set<String> = Set(
                openWorkModels.compactMap { work in
                    guard let slID = work.studentLessonID,
                          let sl = studentLessons.first(where: { $0.id == slID }) else { return nil }
                    let studentIDs = work.participants?.compactMap { UUID(uuidString: $0.studentID) } ?? []
                    return studentIDs.map { sid in
                        "\(sid.uuidString.lowercased())|\(sl.lessonID.lowercased())"
                    }.first
                }
            )
            
            for sl in presented {
                let presentedDate = sl.givenAt ?? sl.createdAt
                let days = schoolDaysSince(presentedDate)
                
                // Exclude if there is any follow-up work linked by studentLessonID
                let hasFollowUpWork = workModelsByStudentLessonID.contains(sl.id) ||
                    sl.resolvedStudentIDs.map { sid in
                        "\(sid.uuidString.lowercased())|\(sl.lessonID.lowercased())"
                    }.contains(where: { workModelsByStudentLessonKey.contains($0) })
                
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
        
        // Pre-group checkIns and notes for work aging (build indices once per compute)
        // These are built from the already-fetched openWorkModels, no additional fetches
        let checkInsByWorkID: [UUID: [WorkCheckIn]] = openWorkModels.reduce(into: [:]) { dict, work in
            dict[work.id] = work.checkIns ?? []
        }
        let notesByWorkID: [UUID: [Note]] = openWorkModels.reduce(into: [:]) { dict, work in
            dict[work.id] = work.unifiedNotes ?? []
        }
        
        #if DEBUG
        let studentLessonsFetchStart = Date()
        #endif
        // StudentLessons are passed in as a parameter (fetched once upstream)
        // No additional fetch needed here
        #if DEBUG
        let studentLessonsFetchDuration = Date().timeIntervalSince(studentLessonsFetchStart)
        print("📊 FollowUpInboxEngine: Processed \(studentLessons.count) StudentLessons (no additional fetch)")
        #endif
        
        var addedWorkIDs: Set<UUID> = []
        
        // Rule 2/3: Work check-in stale and review stale (with Upcoming)
        for work in openWorkModels {
            let status = work.status
            let isActive = status == .active
            let isReview = status == .review
            guard isActive || isReview else { continue }
            
            let workCheckIns = checkInsByWorkID[work.id] ?? []
            let workNotes = notesByWorkID[work.id] ?? []
            let days = WorkAgingPolicy.daysSinceLastTouch(
                for: work,
                modelContext: modelContext,
                checkIns: workCheckIns,
                notes: workNotes
            )
            
            let threshold = isActive ? constants.workStaleOverdueDays : constants.reviewStaleDays
            let bucket: FollowUpInboxItem.Bucket
            if days > threshold { bucket = .overdue }
            else if days == threshold { bucket = .dueToday }
            else {
                let until = max(0, threshold - days)
                if (1...2).contains(until) { bucket = .upcoming } else { continue }
            }
            
            // Resolve display fields
            // Get first participant's student ID (or use studentLesson to find students)
            let participantStudentIDs: [UUID] = (work.participants ?? []).compactMap { UUID(uuidString: $0.studentID) }
            let studentIDs: [UUID] = {
                if !participantStudentIDs.isEmpty {
                    return participantStudentIDs
                }
                // Fallback: try to get from studentLesson
                if let slID = work.studentLessonID,
                   let sl = studentLessons.first(where: { $0.id == slID }) {
                    return sl.resolvedStudentIDs
                }
                return []
            }()
            
            let studentName: String = {
                if let firstID = studentIDs.first, let s = studentsByID[firstID] {
                    return StudentFormatter.displayName(for: s)
                }
                return "Student"
            }()
            
            let lessonTitle: String = {
                // Try to get from studentLesson
                if let slID = work.studentLessonID,
                   let sl = studentLessons.first(where: { $0.id == slID }),
                   let lessonUUID = UUID(uuidString: sl.lessonID),
                   let l = lessonsByID[lessonUUID] {
                    return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
                }
                // Fallback to work title
                let trimmed = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                return "Work"
            }()
            
            let (cid, cname): (UUID?, String) = {
                if let firstID = studentIDs.first { return (firstID, studentName) }
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
                id: "\(kind.rawValue):\(work.id.uuidString)",
                underlyingID: work.id,
                childID: cid,
                childName: cname,
                title: lessonTitle,
                kind: kind,
                statusText: statusText,
                ageDays: days,
                bucket: bucket
            )
            results.append(item)
            addedWorkIDs.insert(work.id)
        }
        
        // Rule 4: Unscheduled open work (needs scheduling inbox)
        for work in openWorkModels {
            let status = work.status
            let isActive = status == .active
            let isReview = status == .review
            guard isActive || isReview else { continue }
            // Skip if already added by Rule 2/3
            guard !addedWorkIDs.contains(work.id) else { continue }
            // Only include when there are no scheduled check-ins and no dueAt
            let workCheckIns = checkInsByWorkID[work.id] ?? []
            let hasScheduledCheckIns = workCheckIns.contains { $0.status == .scheduled }
            guard !hasScheduledCheckIns && work.dueAt == nil else { continue }
            
            // Display fields (same resolution as Rule 2/3)
            let participantStudentIDs: [UUID] = (work.participants ?? []).compactMap { UUID(uuidString: $0.studentID) }
            let studentIDs: [UUID] = {
                if !participantStudentIDs.isEmpty {
                    return participantStudentIDs
                }
                if let slID = work.studentLessonID,
                   let sl = studentLessons.first(where: { $0.id == slID }) {
                    return sl.resolvedStudentIDs
                }
                return []
            }()
            
            let studentName: String = {
                if let firstID = studentIDs.first, let s = studentsByID[firstID] {
                    return StudentFormatter.displayName(for: s)
                }
                return "Student"
            }()
            
            let lessonTitle: String = {
                if let slID = work.studentLessonID,
                   let sl = studentLessons.first(where: { $0.id == slID }),
                   let lessonUUID = UUID(uuidString: sl.lessonID),
                   let l = lessonsByID[lessonUUID] {
                    return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
                }
                let trimmed = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                return "Work"
            }()
            
            let (cid, cname): (UUID?, String) = {
                if let firstID = studentIDs.first { return (firstID, studentName) }
                return (nil, studentName)
            }()
            
            // Age for secondary text
            let days = WorkAgingPolicy.daysSinceLastTouch(
                for: work,
                modelContext: modelContext,
                checkIns: workCheckIns,
                notes: []
            )
            let statusText = "Needs scheduling • \(days)d since touched"
            
            let kind: FollowUpInboxItem.Kind = isActive ? .workCheckIn : .workReview
            let item = FollowUpInboxItem(
                id: "inbox:\(work.id.uuidString)",
                underlyingID: work.id,
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
