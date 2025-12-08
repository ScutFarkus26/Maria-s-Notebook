// BackupManager.swift
// Maria's Toolbox
//
// Provides JSON export/import for SwiftData models.

import Foundation
import SwiftData

// MARK: - Backup payload DTOs

struct BackupPayload: Codable {
    var version: Int
    var createdAt: Date
    var items: [ItemDTO]
    var students: [StudentDTO]
    var lessons: [LessonDTO]
    var studentLessons: [StudentLessonDTO]
    var works: [WorkDTO]
    var subjectOrder: [String]
    var groupOrders: [String: [String]]
    var attendance: [AttendanceRecordDTO]
    var workCompletions: [WorkCompletionRecordDTO]
    var workCheckIns: [WorkCheckInDTO]
    var nonSchoolDays: [NonSchoolDayDTO]
    var schoolDayOverrides: [SchoolDayOverrideDTO]
    var presentNowExcludedNames: String?
    var planningInboxOrder: String?
    var attendanceEmailEnabled: Bool?
    var attendanceEmailTo: String?
    var attendanceEmailFrom: String?
    var lessonAgeWarningDays: Int?
    var lessonAgeOverdueDays: Int?
    var lessonAgeFreshColorHex: String?
    var lessonAgeWarningColorHex: String?
    var lessonAgeOverdueColorHex: String?
    var selectedChecklistSubject: String?
    var lastBackupTimeInterval: Double?

    private enum CodingKeys: String, CodingKey {
        case version, createdAt, items, students, lessons, studentLessons, works, subjectOrder, groupOrders, attendance, workCompletions, workCheckIns
        case nonSchoolDays, schoolDayOverrides, presentNowExcludedNames, planningInboxOrder
        case attendanceEmailEnabled, attendanceEmailTo, attendanceEmailFrom, lessonAgeWarningDays, lessonAgeOverdueDays, lessonAgeFreshColorHex, lessonAgeWarningColorHex, lessonAgeOverdueColorHex, selectedChecklistSubject, lastBackupTimeInterval
    }

    init(
        version: Int,
        createdAt: Date,
        items: [ItemDTO],
        students: [StudentDTO],
        lessons: [LessonDTO],
        studentLessons: [StudentLessonDTO],
        works: [WorkDTO],
        subjectOrder: [String],
        groupOrders: [String: [String]],
        attendance: [AttendanceRecordDTO],
        workCompletions: [WorkCompletionRecordDTO],
        workCheckIns: [WorkCheckInDTO],
        nonSchoolDays: [NonSchoolDayDTO],
        schoolDayOverrides: [SchoolDayOverrideDTO],
        presentNowExcludedNames: String?,
        planningInboxOrder: String?,
        attendanceEmailEnabled: Bool? = nil,
        attendanceEmailTo: String? = nil,
        attendanceEmailFrom: String? = nil,
        lessonAgeWarningDays: Int? = nil,
        lessonAgeOverdueDays: Int? = nil,
        lessonAgeFreshColorHex: String? = nil,
        lessonAgeWarningColorHex: String? = nil,
        lessonAgeOverdueColorHex: String? = nil,
        selectedChecklistSubject: String? = nil,
        lastBackupTimeInterval: Double? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.items = items
        self.students = students
        self.lessons = lessons
        self.studentLessons = studentLessons
        self.works = works
        self.subjectOrder = subjectOrder
        self.groupOrders = groupOrders
        self.attendance = attendance
        self.workCompletions = workCompletions
        self.workCheckIns = workCheckIns
        self.nonSchoolDays = nonSchoolDays
        self.schoolDayOverrides = schoolDayOverrides
        self.presentNowExcludedNames = presentNowExcludedNames
        self.planningInboxOrder = planningInboxOrder
        self.attendanceEmailEnabled = attendanceEmailEnabled
        self.attendanceEmailTo = attendanceEmailTo
        self.attendanceEmailFrom = attendanceEmailFrom
        self.lessonAgeWarningDays = lessonAgeWarningDays
        self.lessonAgeOverdueDays = lessonAgeOverdueDays
        self.lessonAgeFreshColorHex = lessonAgeFreshColorHex
        self.lessonAgeWarningColorHex = lessonAgeWarningColorHex
        self.lessonAgeOverdueColorHex = lessonAgeOverdueColorHex
        self.selectedChecklistSubject = selectedChecklistSubject
        self.lastBackupTimeInterval = lastBackupTimeInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.items = try container.decode([ItemDTO].self, forKey: .items)
        self.students = try container.decode([StudentDTO].self, forKey: .students)
        self.lessons = try container.decodeIfPresent([LessonDTO].self, forKey: .lessons) ?? []
        self.studentLessons = try container.decodeIfPresent([StudentLessonDTO].self, forKey: .studentLessons) ?? []
        self.works = try container.decodeIfPresent([WorkDTO].self, forKey: .works) ?? []
        self.subjectOrder = try container.decodeIfPresent([String].self, forKey: .subjectOrder) ?? []
        self.groupOrders = try container.decodeIfPresent([String: [String]].self, forKey: .groupOrders) ?? [:]
        self.attendance = try container.decodeIfPresent([AttendanceRecordDTO].self, forKey: .attendance) ?? []
        self.workCompletions = try container.decodeIfPresent([WorkCompletionRecordDTO].self, forKey: .workCompletions) ?? []
        self.workCheckIns = try container.decodeIfPresent([WorkCheckInDTO].self, forKey: .workCheckIns) ?? []
        self.nonSchoolDays = try container.decodeIfPresent([NonSchoolDayDTO].self, forKey: .nonSchoolDays) ?? []
        self.schoolDayOverrides = try container.decodeIfPresent([SchoolDayOverrideDTO].self, forKey: .schoolDayOverrides) ?? []
        self.presentNowExcludedNames = try container.decodeIfPresent(String.self, forKey: .presentNowExcludedNames)
        self.planningInboxOrder = try container.decodeIfPresent(String.self, forKey: .planningInboxOrder)
        self.attendanceEmailEnabled = try container.decodeIfPresent(Bool.self, forKey: .attendanceEmailEnabled)
        self.attendanceEmailTo = try container.decodeIfPresent(String.self, forKey: .attendanceEmailTo)
        self.attendanceEmailFrom = try container.decodeIfPresent(String.self, forKey: .attendanceEmailFrom)
        self.lessonAgeWarningDays = try container.decodeIfPresent(Int.self, forKey: .lessonAgeWarningDays)
        self.lessonAgeOverdueDays = try container.decodeIfPresent(Int.self, forKey: .lessonAgeOverdueDays)
        self.lessonAgeFreshColorHex = try container.decodeIfPresent(String.self, forKey: .lessonAgeFreshColorHex)
        self.lessonAgeWarningColorHex = try container.decodeIfPresent(String.self, forKey: .lessonAgeWarningColorHex)
        self.lessonAgeOverdueColorHex = try container.decodeIfPresent(String.self, forKey: .lessonAgeOverdueColorHex)
        self.selectedChecklistSubject = try container.decodeIfPresent(String.self, forKey: .selectedChecklistSubject)
        self.lastBackupTimeInterval = try container.decodeIfPresent(Double.self, forKey: .lastBackupTimeInterval)
    }
}

struct ItemDTO: Codable {
    var id: UUID
    var timestamp: Date
}

struct StudentDTO: Codable {
    enum Level: String, Codable, CaseIterable {
        case lower = "Lower"
        case upper = "Upper"
    }
    var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date
    var dateStarted: Date?
    var level: Level
    var nextLessons: [UUID]
    var manualOrder: Int
}

struct LessonDTO: Codable {
    var id: UUID
    var name: String
    var subject: String
    var group: String
    var orderInGroup: Int
    var subheading: String
    var writeUp: String

    private enum CodingKeys: String, CodingKey {
        case id, name, subject, group, orderInGroup, subheading, writeUp
    }

    init(id: UUID, name: String, subject: String, group: String, orderInGroup: Int, subheading: String, writeUp: String) {
        self.id = id
        self.name = name
        self.subject = subject
        self.group = group
        self.orderInGroup = orderInGroup
        self.subheading = subheading
        self.writeUp = writeUp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.subject = try container.decode(String.self, forKey: .subject)
        self.group = try container.decode(String.self, forKey: .group)
        self.orderInGroup = try container.decodeIfPresent(Int.self, forKey: .orderInGroup) ?? 0
        self.subheading = try container.decode(String.self, forKey: .subheading)
        self.writeUp = try container.decode(String.self, forKey: .writeUp)
    }
}

struct StudentLessonDTO: Codable {
    var id: UUID
    var lessonID: UUID
    var studentIDs: [UUID]
    var createdAt: Date
    var scheduledFor: Date?
    var givenAt: Date?
    var isPresented: Bool
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String
    var studentGroupKey: String?

    private enum CodingKeys: String, CodingKey {
        case id, lessonID, studentIDs, createdAt, scheduledFor, givenAt, isPresented, notes, needsPractice, needsAnotherPresentation, followUpWork, studentGroupKey
    }

    init(
        id: UUID,
        lessonID: UUID,
        studentIDs: [UUID],
        createdAt: Date,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsPractice: Bool,
        needsAnotherPresentation: Bool,
        followUpWork: String,
        studentGroupKey: String? = nil
    ) {
        self.id = id
        self.lessonID = lessonID
        self.studentIDs = studentIDs
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.studentGroupKey = studentGroupKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.lessonID = try container.decode(UUID.self, forKey: .lessonID)
        self.studentIDs = try container.decode([UUID].self, forKey: .studentIDs)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.scheduledFor = try container.decodeIfPresent(Date.self, forKey: .scheduledFor)
        let givenAt = try container.decodeIfPresent(Date.self, forKey: .givenAt)
        self.givenAt = givenAt
        self.isPresented = try container.decodeIfPresent(Bool.self, forKey: .isPresented) ?? (givenAt != nil)
        self.notes = try container.decode(String.self, forKey: .notes)
        self.needsPractice = try container.decode(Bool.self, forKey: .needsPractice)
        self.needsAnotherPresentation = try container.decode(Bool.self, forKey: .needsAnotherPresentation)
        self.followUpWork = try container.decode(String.self, forKey: .followUpWork)
        self.studentGroupKey = try container.decodeIfPresent(String.self, forKey: .studentGroupKey)
    }
}

struct WorkParticipantDTO: Codable {
    var studentID: UUID
    var completedAt: Date?
}

struct WorkDTO: Codable {
    var id: UUID
    var title: String
    var studentIDs: [UUID]
    var workType: String
    var studentLessonID: UUID?
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    var participants: [WorkParticipantDTO]

    private enum CodingKeys: String, CodingKey { case id, title, studentIDs, workType, studentLessonID, notes, createdAt, completedAt, participants }

    init(id: UUID, title: String, studentIDs: [UUID], workType: String, studentLessonID: UUID?, notes: String, createdAt: Date, completedAt: Date?, participants: [WorkParticipantDTO]) {
        self.id = id
        self.title = title
        self.studentIDs = studentIDs
        self.workType = workType
        self.studentLessonID = studentLessonID
        self.notes = notes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.participants = participants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.studentIDs = try container.decode([UUID].self, forKey: .studentIDs)
        self.workType = try container.decode(String.self, forKey: .workType)
        self.studentLessonID = try container.decodeIfPresent(UUID.self, forKey: .studentLessonID)
        self.notes = try container.decode(String.self, forKey: .notes)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.participants = try container.decodeIfPresent([WorkParticipantDTO].self, forKey: .participants) ?? []
    }
}

struct AttendanceRecordDTO: Codable {
    var id: UUID
    var studentID: UUID
    var date: Date
    var status: String
    var note: String?
}

struct WorkCompletionRecordDTO: Codable {
    var id: UUID
    var workID: UUID
    var studentID: UUID
    var completedAt: Date
    var note: String
}

struct WorkCheckInDTO: Codable {
    var id: UUID
    var workID: UUID
    var date: Date
    var status: String
    var purpose: String
    var note: String
}

struct NonSchoolDayDTO: Codable {
    var id: UUID
    var date: Date
    var reason: String?
}

struct SchoolDayOverrideDTO: Codable {
    var id: UUID
    var date: Date
    var note: String?
}

// MARK: - Backup Manager

enum BackupManager {
    /// Current backup format version. Bump if you change the payload shape.
    static let currentVersion: Int = 16

    /// Create JSON data representing the current database state.
    static func makeBackupData(using context: ModelContext) throws -> Data {
        // Fetch all Items
        let itemsFetch = FetchDescriptor<Item>()
        let items = try context.fetch(itemsFetch)
        let itemsDTO: [ItemDTO] = items.map { item in
            // Item has no id in the model; synthesize a stable one from timestamp+UUID? We'll use mirror via objectID not available.
            // Instead, embed a generated UUID per export. Since Item has no id property, we cannot preserve identity across restore.
            // We'll assign new IDs on import for Item; keep a transient id here.
            ItemDTO(id: UUID(), timestamp: item.timestamp)
        }

        // Fetch all Students
        let studentsFetch = FetchDescriptor<Student>()
        let students = try context.fetch(studentsFetch)
        let studentsDTO: [StudentDTO] = students.map { s in
            StudentDTO(
                id: s.id,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                dateStarted: s.dateStarted,
                level: StudentDTO.Level(rawValue: s.level.rawValue) ?? .lower,
                nextLessons: s.nextLessons,
                manualOrder: s.manualOrder
            )
        }

        // Fetch all Lessons
        let lessonsFetch = FetchDescriptor<Lesson>()
        let lessons = try context.fetch(lessonsFetch)
        let lessonsDTO: [LessonDTO] = lessons.map { l in
            LessonDTO(
                id: l.id,
                name: l.name,
                subject: l.subject,
                group: l.group,
                orderInGroup: l.orderInGroup,
                subheading: l.subheading,
                writeUp: l.writeUp
            )
        }
        
        // Fetch all StudentLessons
        let slFetch = FetchDescriptor<StudentLesson>()
        let sls = try context.fetch(slFetch)
        let studentLessonsDTO: [StudentLessonDTO] = sls.map { sl in
            StudentLessonDTO(
                id: sl.id,
                lessonID: sl.resolvedLessonID,
                studentIDs: sl.resolvedStudentIDs,
                createdAt: sl.createdAt,
                scheduledFor: sl.scheduledFor,
                givenAt: sl.givenAt,
                isPresented: sl.isPresented,
                notes: sl.notes,
                needsPractice: sl.needsPractice,
                needsAnotherPresentation: sl.needsAnotherPresentation,
                followUpWork: sl.followUpWork,
                studentGroupKey: sl.studentGroupKeyPersisted.isEmpty ? nil : sl.studentGroupKeyPersisted
            )
        }

        // Fetch all WorkModel objects
        let worksFetch = FetchDescriptor<WorkModel>()
        let works = try context.fetch(worksFetch)
        let worksDTO: [WorkDTO] = works.map { w in
            WorkDTO(
                id: w.id,
                title: w.title,
                studentIDs: w.participants.map { $0.studentID },
                workType: w.workType.rawValue,
                studentLessonID: w.studentLessonID,
                notes: w.notes,
                createdAt: w.createdAt,
                completedAt: w.completedAt,
                participants: w.participants.map { p in
                    WorkParticipantDTO(studentID: p.studentID, completedAt: p.completedAt)
                }
            )
        }

        // Fetch all AttendanceRecords
        let attendanceFetch = FetchDescriptor<AttendanceRecord>()
        let attendance = try context.fetch(attendanceFetch)
        let attendanceDTO: [AttendanceRecordDTO] = attendance.map { rec in
            AttendanceRecordDTO(
                id: rec.id,
                studentID: rec.studentID,
                date: rec.date,
                status: rec.status.rawValue,
                note: rec.note
            )
        }

        // Fetch all WorkCompletionRecords
        let completionsFetch = FetchDescriptor<WorkCompletionRecord>()
        let completions = try context.fetch(completionsFetch)
        let workCompletionsDTO: [WorkCompletionRecordDTO] = completions.map { rc in
            WorkCompletionRecordDTO(
                id: rc.id,
                workID: rc.workID,
                studentID: rc.studentID,
                completedAt: rc.completedAt,
                note: rc.note
            )
        }

        // Fetch all WorkCheckIns
        let checkInsFetch = FetchDescriptor<WorkCheckIn>()
        let checkIns = try context.fetch(checkInsFetch)
        let workCheckInsDTO: [WorkCheckInDTO] = checkIns.map { ci in
            WorkCheckInDTO(
                id: ci.id,
                workID: ci.workID,
                date: ci.date,
                status: ci.status.rawValue,
                purpose: ci.purpose,
                note: ci.note
            )
        }

        // Fetch school calendar entities
        let nonSchoolDaysFetch = FetchDescriptor<NonSchoolDay>()
        let nonSchoolDays = try context.fetch(nonSchoolDaysFetch)
        let nonSchoolDaysDTO: [NonSchoolDayDTO] = nonSchoolDays.map { d in
            NonSchoolDayDTO(id: d.id, date: d.date, reason: d.reason)
        }

        let overridesFetch = FetchDescriptor<SchoolDayOverride>()
        let overrides = try context.fetch(overridesFetch)
        let schoolDayOverridesDTO: [SchoolDayOverrideDTO] = overrides.map { o in
            SchoolDayOverrideDTO(id: o.id, date: o.date, note: o.note)
        }

        // Read small user preferences that affect planning/filters
        let presentNowExcludedNames = UserDefaults.standard.string(forKey: "StudentsView.presentNow.excludedNames")
        let planningInboxOrder = UserDefaults.standard.string(forKey: "PlanningInbox.order")

        // Read new preferences for backup
        let attendanceEmailEnabled = UserDefaults.standard.object(forKey: AttendanceEmailPrefs.enabledKey) as? Bool
        let attendanceEmailTo = UserDefaults.standard.string(forKey: AttendanceEmailPrefs.toKey)
        let attendanceEmailFrom = UserDefaults.standard.string(forKey: AttendanceEmailPrefs.fromKey)
        let lessonAgeWarningDays = UserDefaults.standard.object(forKey: "LessonAge.warningDays") as? Int
        let lessonAgeOverdueDays = UserDefaults.standard.object(forKey: "LessonAge.overdueDays") as? Int
        let lessonAgeFreshColorHex = UserDefaults.standard.string(forKey: "LessonAge.freshColorHex")
        let lessonAgeWarningColorHex = UserDefaults.standard.string(forKey: "LessonAge.warningColorHex")
        let lessonAgeOverdueColorHex = UserDefaults.standard.string(forKey: "LessonAge.overdueColorHex")
        let selectedChecklistSubject = UserDefaults.standard.string(forKey: "StudentDetailView.selectedChecklistSubject")
        let lastBackupTimeInterval = UserDefaults.standard.object(forKey: "lastBackupTimeInterval") as? Double

        // Compute subjects and per-subject group orders from current data and saved preferences
        let existingSubjects: [String] = Array(Set(lessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let subjectOrder: [String] = FilterOrderStore.loadSubjectOrder(existing: existingSubjects)

        func groups(for subject: String) -> [String] {
            let gs = lessons
                .filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
                .map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(gs)).sorted()
        }

        var groupOrders: [String: [String]] = [:]
        for subject in subjectOrder {
            let existingGroups = groups(for: subject)
            let order = FilterOrderStore.loadGroupOrder(for: subject, existing: existingGroups)
            if !order.isEmpty { groupOrders[subject] = order }
        }

        let payload = BackupPayload(
            version: currentVersion,
            createdAt: Date(),
            items: itemsDTO,
            students: studentsDTO,
            lessons: lessonsDTO,
            studentLessons: studentLessonsDTO,
            works: worksDTO,
            subjectOrder: subjectOrder,
            groupOrders: groupOrders,
            attendance: attendanceDTO,
            workCompletions: workCompletionsDTO,
            workCheckIns: workCheckInsDTO,
            nonSchoolDays: nonSchoolDaysDTO,
            schoolDayOverrides: schoolDayOverridesDTO,
            presentNowExcludedNames: presentNowExcludedNames,
            planningInboxOrder: planningInboxOrder,
            attendanceEmailEnabled: attendanceEmailEnabled,
            attendanceEmailTo: attendanceEmailTo,
            attendanceEmailFrom: attendanceEmailFrom,
            lessonAgeWarningDays: lessonAgeWarningDays,
            lessonAgeOverdueDays: lessonAgeOverdueDays,
            lessonAgeFreshColorHex: lessonAgeFreshColorHex,
            lessonAgeWarningColorHex: lessonAgeWarningColorHex,
            lessonAgeOverdueColorHex: lessonAgeOverdueColorHex,
            selectedChecklistSubject: selectedChecklistSubject,
            lastBackupTimeInterval: lastBackupTimeInterval
        )
        let encoder = JSONEncoder()
        // Use compact encoding for smaller backups and faster encode
        // (Pretty printing and sorted keys can be re-enabled for debugging if needed)
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Import JSON backup data into the database, replacing existing content.
    /// - Note: This will delete all existing Items, Lessons and Students before inserting from backup.
    static func restore(from data: Data, using context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        // Optionally validate version
        guard payload.version <= currentVersion else {
            throw NSError(domain: "BackupManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup file was created by a newer app version."])
        }

        // Delete existing data first
        try deleteAll(using: context)

        // Insert Items
        for dto in payload.items {
            let newItem = Item(timestamp: dto.timestamp)
            context.insert(newItem)
        }

        // Insert Lessons (preserving IDs)
        for dto in payload.lessons {
            let lesson = Lesson(
                id: dto.id,
                name: dto.name,
                subject: dto.subject,
                group: dto.group,
                subheading: dto.subheading,
                writeUp: dto.writeUp
            )
            lesson.orderInGroup = dto.orderInGroup
            context.insert(lesson)
        }

        // Insert Students (preserving IDs)
        for dto in payload.students {
            let level: Student.Level = (dto.level == .upper) ? .upper : .lower
            let student = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: level,
                dateStarted: dto.dateStarted,
                nextLessons: dto.nextLessons,
                manualOrder: dto.manualOrder
            )
            context.insert(student)
        }

        // Insert StudentLessons (preserving IDs)
        for dto in payload.studentLessons {
            let sl = StudentLesson(
                id: dto.id,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs,
                createdAt: dto.createdAt,
                scheduledFor: dto.scheduledFor,
                givenAt: dto.givenAt,
                notes: dto.notes,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork
            )
            sl.isPresented = dto.isPresented
            if let groupKey = dto.studentGroupKey {
                sl.studentGroupKeyPersisted = groupKey
            }
            context.insert(sl)
        }
        
        // Insert Works (preserving IDs) if present
        if !payload.works.isEmpty {
            for dto in payload.works {
                guard let workTypeEnum = WorkModel.WorkType(rawValue: dto.workType) else {
                    // skip unknown workTypes
                    continue
                }
                let participants: [WorkParticipantEntity]
                if dto.participants.isEmpty {
                    participants = dto.studentIDs.map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil) }
                } else {
                    participants = dto.participants.map { part in
                        WorkParticipantEntity(studentID: part.studentID, completedAt: part.completedAt)
                    }
                }
                let work = WorkModel(
                    id: dto.id,
                    title: dto.title,
                    workType: workTypeEnum,
                    studentLessonID: dto.studentLessonID,
                    notes: dto.notes,
                    createdAt: dto.createdAt,
                    completedAt: dto.completedAt,
                    participants: participants
                )
                for p in work.participants { p.work = work }
                context.insert(work)
            }
        }

        // Insert AttendanceRecords (preserving IDs)
        if !payload.attendance.isEmpty {
            for dto in payload.attendance {
                let rec = AttendanceRecord(
                    id: dto.id,
                    studentID: dto.studentID,
                    date: dto.date,
                    status: AttendanceStatus(rawValue: dto.status) ?? .unmarked,
                    note: dto.note
                )
                context.insert(rec)
            }
        }

        // Insert WorkCompletionRecords (preserving IDs)
        if !payload.workCompletions.isEmpty {
            for dto in payload.workCompletions {
                let rec = WorkCompletionRecord(
                    id: dto.id,
                    workID: dto.workID,
                    studentID: dto.studentID,
                    completedAt: dto.completedAt,
                    note: dto.note
                )
                context.insert(rec)
            }
        }

        // Insert WorkCheckIns (preserving IDs)
        if !payload.workCheckIns.isEmpty {
            // Build a map of works by ID to wire relationship
            let allWorks = try context.fetch(FetchDescriptor<WorkModel>())
            let worksByID = Dictionary(uniqueKeysWithValues: allWorks.map { ($0.id, $0) })
            for dto in payload.workCheckIns {
                let checkIn = WorkCheckIn(
                    id: dto.id,
                    workID: dto.workID,
                    date: dto.date,
                    status: WorkCheckInStatus(rawValue: dto.status) ?? .scheduled,
                    purpose: dto.purpose,
                    note: dto.note,
                    work: worksByID[dto.workID]
                )
                context.insert(checkIn)
            }
        }

        // Backward compatibility: synthesize unscheduled StudentLesson records if missing but nextLessons present
        if payload.studentLessons.isEmpty {
            let existingLessonIDs = Set(try context.fetch(FetchDescriptor<Lesson>()).map { $0.id })
            let studentMap = try context.fetch(FetchDescriptor<Student>()).reduce(into: [UUID: Student]()) { $0[$1.id] = $1 }
            for sDTO in payload.students where !sDTO.nextLessons.isEmpty {
                guard let student = studentMap[sDTO.id] else { continue }
                for lID in sDTO.nextLessons where existingLessonIDs.contains(lID) {
                    let sl = StudentLesson(
                        lessonID: lID,
                        studentIDs: [student.id],
                        createdAt: payload.createdAt,
                        scheduledFor: nil,
                        givenAt: nil,
                        notes: "",
                        needsPractice: false,
                        needsAnotherPresentation: false,
                        followUpWork: ""
                    )
                    context.insert(sl)
                }
            }
        }

        // Restore subject and group ordering preferences if present
        if !payload.subjectOrder.isEmpty {
            FilterOrderStore.saveSubjectOrder(payload.subjectOrder)
        }
        if !payload.groupOrders.isEmpty {
            for (subject, order) in payload.groupOrders {
                FilterOrderStore.saveGroupOrder(order, for: subject)
            }
        }

        // After inserting all entities, wire up relationships for StudentLesson using snapshot IDs
        do {
            let allLessons = try context.fetch(FetchDescriptor<Lesson>())
            let lessonsByID = Dictionary(uniqueKeysWithValues: allLessons.map { ($0.id, $0) })
            let allStudents = try context.fetch(FetchDescriptor<Student>())
            let studentsByID = Dictionary(uniqueKeysWithValues: allStudents.map { ($0.id, $0) })
            let allSLs = try context.fetch(FetchDescriptor<StudentLesson>())
            for sl in allSLs {
                sl.lesson = lessonsByID[sl.lessonID]
                sl.students = sl.studentIDs.compactMap { studentsByID[$0] }
            }
            // Wire WorkCheckIn relationships to WorkModel
            let allWorks2 = try context.fetch(FetchDescriptor<WorkModel>())
            let worksByID2 = Dictionary(uniqueKeysWithValues: allWorks2.map { ($0.id, $0) })
            let allCIs = try context.fetch(FetchDescriptor<WorkCheckIn>())
            for ci in allCIs {
                ci.work = worksByID2[ci.workID]
            }
        } catch {
            // If wiring relationships fails, we still keep IDs; UI will fall back to snapshots
        }

        // Insert NonSchoolDay and SchoolDayOverride entities
        if !payload.nonSchoolDays.isEmpty {
            for dto in payload.nonSchoolDays {
                let day = NonSchoolDay(id: dto.id, date: dto.date, reason: dto.reason)
                context.insert(day)
            }
        }
        if !payload.schoolDayOverrides.isEmpty {
            for dto in payload.schoolDayOverrides {
                let ov = SchoolDayOverride(id: dto.id, date: dto.date, note: dto.note)
                context.insert(ov)
            }
        }

        // Restore small preferences
        if let s = payload.presentNowExcludedNames {
            UserDefaults.standard.set(s, forKey: "StudentsView.presentNow.excludedNames")
        }
        if let s = payload.planningInboxOrder {
            UserDefaults.standard.set(s, forKey: "PlanningInbox.order")
        }

        // Restore new preferences from backup if present
        if let attendanceEmailEnabled = payload.attendanceEmailEnabled {
            UserDefaults.standard.set(attendanceEmailEnabled, forKey: AttendanceEmailPrefs.enabledKey)
        }
        if let attendanceEmailTo = payload.attendanceEmailTo {
            UserDefaults.standard.set(attendanceEmailTo, forKey: AttendanceEmailPrefs.toKey)
        }
        if let attendanceEmailFrom = payload.attendanceEmailFrom {
            UserDefaults.standard.set(attendanceEmailFrom, forKey: AttendanceEmailPrefs.fromKey)
        }
        if let lessonAgeWarningDays = payload.lessonAgeWarningDays {
            UserDefaults.standard.set(lessonAgeWarningDays, forKey: "LessonAge.warningDays")
        }
        if let lessonAgeOverdueDays = payload.lessonAgeOverdueDays {
            UserDefaults.standard.set(lessonAgeOverdueDays, forKey: "LessonAge.overdueDays")
        }
        if let lessonAgeFreshColorHex = payload.lessonAgeFreshColorHex {
            UserDefaults.standard.set(lessonAgeFreshColorHex, forKey: "LessonAge.freshColorHex")
        }
        if let lessonAgeWarningColorHex = payload.lessonAgeWarningColorHex {
            UserDefaults.standard.set(lessonAgeWarningColorHex, forKey: "LessonAge.warningColorHex")
        }
        if let lessonAgeOverdueColorHex = payload.lessonAgeOverdueColorHex {
            UserDefaults.standard.set(lessonAgeOverdueColorHex, forKey: "LessonAge.overdueColorHex")
        }
        if let selectedChecklistSubject = payload.selectedChecklistSubject {
            UserDefaults.standard.set(selectedChecklistSubject, forKey: "StudentDetailView.selectedChecklistSubject")
        }
        if let lastBackupTimeInterval = payload.lastBackupTimeInterval {
            UserDefaults.standard.set(lastBackupTimeInterval, forKey: "lastBackupTimeInterval")
        }

        try context.save()
    }

    /// Delete all Items, Lessons, Students, StudentLessons and Works from the store.
    static func deleteAll(using context: ModelContext) throws {
        // Delete Items
        do {
            let items = try context.fetch(FetchDescriptor<Item>())
            for obj in items { context.delete(obj) }
        }
        // Delete Lessons
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            for obj in lessons { context.delete(obj) }
        }
        // Delete Students
        do {
            let students = try context.fetch(FetchDescriptor<Student>())
            for obj in students { context.delete(obj) }
        }
        // Delete StudentLessons
        do {
            let sls = try context.fetch(FetchDescriptor<StudentLesson>())
            for obj in sls { context.delete(obj) }
        }
        // Delete Works
        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            for obj in works { context.delete(obj) }
        }
        // Delete WorkCheckIns
        do {
            let cis = try context.fetch(FetchDescriptor<WorkCheckIn>())
            for obj in cis { context.delete(obj) }
        }
        // Delete WorkCompletionRecords
        do {
            let wcrs = try context.fetch(FetchDescriptor<WorkCompletionRecord>())
            for obj in wcrs { context.delete(obj) }
        }
        // Delete AttendanceRecords
        do {
            let atts = try context.fetch(FetchDescriptor<AttendanceRecord>())
            for obj in atts { context.delete(obj) }
        }
        // Delete NonSchoolDay
        do {
            let days = try context.fetch(FetchDescriptor<NonSchoolDay>())
            for obj in days { context.delete(obj) }
        }
        // Delete SchoolDayOverride
        do {
            let overrides = try context.fetch(FetchDescriptor<SchoolDayOverride>())
            for obj in overrides { context.delete(obj) }
        }
        try context.save()
    }
}

