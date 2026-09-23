import CoreData
import Foundation

// The roster lists and the table caches, read only when their inputs move.
//
// `filteredStudents` fetches the Student table and filters/sorts it; the
// roster screen reads its two lists four to six times per render, so the
// memo below keeps the last result per query until a Student changes. The
// fetch itself is unchanged, so the order is exactly the fetch's order.
//
// The table caches (days since last lesson, next-lesson names, latest
// observation dates) read lessons, presented assignments, notes and note
// links; an attendance tap moves none of those, so it reloads attendance
// alone unless one of them changed too.

extension StudentsViewModel {

    /// Everything `filteredStudents` answers from besides the Student rows.
    struct RosterQuery: Hashable {
        let filter: StudentsFilter
        let sortOrder: SortOrder
        let searchString: String
        /// The birthday sort counts from the start of today.
        let day: Date
        let presentNowIDs: Set<UUID>?
        let showTestStudents: Bool
        let testStudentNames: String
    }

    struct RosterMemoEntry {
        let generation: Int
        let students: [CDStudent]
    }

    /// The day, and the counter epoch the school-day counts clamp to.
    struct TableCacheStamp: Equatable {
        let day: Date
        let epoch: Date?

        init(calendar: Calendar) {
            day = calendar.startOfDay(for: Date())
            epoch = SchoolYearCounters.epoch
        }
    }

    /// What `computeDaysSinceLastLessonCache` and `loadTableCaches` read:
    /// the students (their next lessons), lessons, presented assignments,
    /// notes and their links, and the school calendar the day count uses.
    nonisolated static let tableCacheInputEntities: Set<String> = [
        "Student", "Lesson", "LessonAssignment", "Note", "NoteStudentLink",
        "NonSchoolDay", "SchoolDayOverride"
    ]

    /// Most roster queries kept at once (one per search keystroke otherwise).
    private static let rosterMemoLimit = 8

    // MARK: - Roster memo

    /// `filteredStudents`, fetched again only when a Student changed or the
    /// query differs from one already answered since the last change.
    func memoizedFilteredStudents(
        viewContext: NSManagedObjectContext,
        filter: StudentsFilter,
        sortOrder: SortOrder,
        searchString: String = "",
        presentNowIDs: Set<UUID>? = nil,
        showTestStudents: Bool = true,
        testStudentNames: String = ""
    ) -> [CDStudent] {
        let generation = currentStudentGeneration(in: viewContext)
        let today = Date()
        let query = RosterQuery(
            filter: filter, sortOrder: sortOrder, searchString: searchString,
            day: AppCalendar.shared.startOfDay(for: today), presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents, testStudentNames: testStudentNames
        )
        if let hit = rosterMemo[query], hit.generation == generation {
            return hit.students
        }
        rosterFetchCount += 1
        let students = filteredStudents(
            viewContext: viewContext, filter: filter, sortOrder: sortOrder,
            searchString: searchString, today: today, presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents, testStudentNames: testStudentNames
        )
        rosterMemo = rosterMemo.filter { $0.value.generation == generation }
        if rosterMemo.count >= Self.rosterMemoLimit { rosterMemo.removeAll() }
        rosterMemo[query] = RosterMemoEntry(generation: generation, students: students)
        return students
    }

    /// Bumped whenever a Student changed since the last read (or one has an
    /// unannounced pending edit, so every read refetches until it is saved).
    private func currentStudentGeneration(in context: NSManagedObjectContext) -> Int {
        let flag: ManagedObjectChangeFlag
        if let existing = studentChanges, existing.watches(context) {
            flag = existing
        } else {
            flag = ManagedObjectChangeFlag(entityNames: ["Student"], context: context)
            studentChanges = flag
            studentGeneration += 1
        }
        if flag.consume(pendingIn: context) { studentGeneration += 1 }
        return studentGeneration
    }

    // MARK: - Table caches

    func tableCacheFlag(for context: NSManagedObjectContext) -> ManagedObjectChangeFlag {
        if let existing = tableCacheInputs, existing.watches(context) { return existing }
        let flag = ManagedObjectChangeFlag(entityNames: Self.tableCacheInputEntities, context: context)
        tableCacheInputs = flag
        return flag
    }

    /// The lessons some student lists as next, fetched by id — the only
    /// lessons the next-lesson names look up.
    static func nextLessons(for students: [CDStudent], in context: NSManagedObjectContext) -> [CDLesson] {
        let ids = Set(students.flatMap(\.nextLessonUUIDs))
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        return context.safeFetch(request)
    }

    /// Each student's latest observation: a note indexed to her
    /// (`searchIndexStudentID`) or linked to her through a scoped (not
    /// whole-class) note, dated `updatedAt ?? createdAt`.
    ///
    /// Reads three columns per row as dictionaries when the context has no
    /// unsaved changes (a dictionary fetch cannot see them); the object path
    /// otherwise, so the answer is the same either way.
    static func latestObservationDates(
        for studentIDs: Set<UUID>, in context: NSManagedObjectContext
    ) -> [UUID: Date] {
        var latest: [UUID: Date] = [:]
        func note(_ studentID: UUID?, _ date: Date?) {
            guard let studentID, studentIDs.contains(studentID), let date else { return }
            latest[studentID] = max(latest[studentID] ?? .distantPast, date)
        }

        if !context.hasChanges,
           let noteRows = directNoteRows(in: context),
           let linkRows = linkRows(in: context) {
            for row in noteRows {
                note(row["student"] as? UUID, (row["updatedAt"] as? Date) ?? (row["createdAt"] as? Date))
            }
            for row in linkRows {
                note(
                    (row["student"] as? String).flatMap(UUID.init(uuidString:)),
                    (row["updatedAt"] as? Date) ?? (row["createdAt"] as? Date)
                )
            }
            return latest
        }

        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(format: "searchIndexStudentID != nil")
        for row in context.safeFetch(noteRequest) {
            note(row.searchIndexStudentID, row.updatedAt ?? row.createdAt)
        }
        let linkRequest: NSFetchRequest<CDNoteStudentLink> = NSFetchRequest(entityName: "NoteStudentLink")
        linkRequest.relationshipKeyPathsForPrefetching = ["note"]
        for link in context.safeFetch(linkRequest) {
            guard let linked = link.note, !linked.scopeIsAll else { continue }
            note(link.studentIDUUID, linked.updatedAt ?? linked.createdAt)
        }
        return latest
    }

    private static func column(
        _ keyPath: String, as name: String, type: NSAttributeType
    ) -> NSExpressionDescription {
        let description = NSExpressionDescription()
        description.name = name
        description.expression = NSExpression(forKeyPath: keyPath)
        description.expressionResultType = type
        return description
    }

    static func directNoteRows(in context: NSManagedObjectContext) -> [NSDictionary]? {
        let request = NSFetchRequest<NSDictionary>(entityName: "Note")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "searchIndexStudentID != nil")
        request.propertiesToFetch = [
            column("searchIndexStudentID", as: "student", type: .UUIDAttributeType),
            column("updatedAt", as: "updatedAt", type: .dateAttributeType),
            column("createdAt", as: "createdAt", type: .dateAttributeType)
        ]
        return try? context.fetch(request)
    }

    static func linkRows(in context: NSManagedObjectContext) -> [NSDictionary]? {
        let request = NSFetchRequest<NSDictionary>(entityName: "NoteStudentLink")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "note != nil AND note.scopeIsAll == NO")
        request.propertiesToFetch = [
            column("studentID", as: "student", type: .stringAttributeType),
            column("note.updatedAt", as: "updatedAt", type: .dateAttributeType),
            column("note.createdAt", as: "createdAt", type: .dateAttributeType)
        ]
        return try? context.fetch(request)
    }
}
