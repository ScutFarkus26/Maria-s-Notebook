//
//  LessonAssignmentHistoryView.swift
//  Maria's Notebook
//
//  History view for presented LessonAssignments.
//  Phase 5 migration: This view reads from CDLessonAssignment instead of Presentation.
//
//  Split into multiple files for maintainability:
//  - LessonAssignmentHistoryView.swift (this file) - Core struct, state, computed properties, body
//  - LessonAssignmentHistoryView+Filters.swift - Filter bar UI and filter labels
//  - LessonAssignmentHistoryView+Rows.swift - Row rendering (mainContent, assignmentsList, row, noteRow)
//  - LessonAssignmentHistoryView+DataLoading.swift - Data loading, cache building, delete
//

import SwiftUI
import CoreData
import OSLog

struct LessonAssignmentHistoryView: View {
    static let logger = Logger.presentations
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // PAGINATION: Load assignments in batches instead of all at once
    static let initialLoadCount = 50
    static let loadMoreCount = 50

    @State var loadedAssignments: [CDLessonAssignment] = []
    @State var hasLoadedMore = false

    // Fetch Lessons (for lookup)
    @FetchRequest(sortDescriptors: []) var lessons: FetchedResults<CDLesson>
    // Fetch Students (for lookup)
    @FetchRequest(sortDescriptors: []) var studentsRaw: FetchedResults<CDStudent>

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(Array(studentsRaw).uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Double deduplication ensures no crashes even with CloudKit sync race conditions
    var safeStudents: [CDStudent] {
        students.uniqueByID
    }

    // Fetch Notes that are attached to a lesson assignment
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]) var recentNotes: FetchedResults<CDNote>

    // Use @Query for change detection only - track count for efficient change detection
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)], predicate: NSPredicate(format: "stateRaw == \"presented\""))
    var allAssignmentsForChangeDetection: FetchedResults<CDLessonAssignment>

    @State var selectedAssignment: CDLessonAssignment?
    @State var notesCountCache: [String: Int] = [:]
    @State var studentNameCache: [UUID: String] = [:]
    @State var lessonTitleCache: [UUID: String] = [:]
    @State var hasBuiltCachesOnce: Bool = false

    // CDTrackEntity counts for efficient change detection (avoids expensive .map operations)
    @State var lastAssignmentCount: Int = 0
    @State var lastNotesCount: Int = 0
    @State var lastLessonsCount: Int = 0
    @State var lastStudentsCount: Int = 0

    // Filter state
    @State var selectedStudentIDs: Set<UUID> = []
    @State var selectedSubjects: Set<String> = []
    @State var searchText: String = ""

    @AppStorage(UserDefaultsKeys.presentationHistoryNameDisplayStyle)
    private var nameDisplayStyleRaw: String = "firstLastInitial"
    private enum NameDisplayStyle: String, Sendable {
        case initials, firstLastInitial
    }
    private var nameDisplayStyle: NameDisplayStyle {
        NameDisplayStyle(rawValue: nameDisplayStyleRaw) ?? .firstLastInitial
    }

    func displayName(for s: CDStudent) -> String {
        let first = s.firstName.trimmed()
        let last = s.lastName.trimmed()
        switch nameDisplayStyle {
        case .initials:
            let fi = first.first.map { String($0).uppercased() } ?? ""
            let li = last.first.map { String($0).uppercased() } ?? ""
            return fi + li
        case .firstLastInitial:
            let li = last.first.map { String($0).uppercased() } ?? ""
            return li.isEmpty ? first : "\(first) \(li)."
        }
    }

    // Maps for quick lookup
    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var lessonsByID: [UUID: CDLesson] {
        Dictionary(lessons.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    var studentsByID: [UUID: CDStudent] {
        Dictionary(safeStudents.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Available subjects from lessons (sorted, non-empty only)
    var availableSubjects: [String] {
        let subjects = Set(lessons.map { $0.subject.trimmed() })
            .filter { !$0.isEmpty }
        return subjects.sorted()
    }

    // Filtered assignments
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    var filteredAssignments: [CDLessonAssignment] {
        loadedAssignments.uniqueByID.filter { la in
            // CDStudent filter
            if !selectedStudentIDs.isEmpty {
                let assignmentStudentIDs = Set(la.studentUUIDs)
                if assignmentStudentIDs.isDisjoint(with: selectedStudentIDs) { return false }
            }

            // Subject filter
            if !selectedSubjects.isEmpty {
                if let lessonID = la.lessonIDUUID,
                   let lesson = lessonsByID[lessonID] {
                    let subject = lesson.subject.trimmed()
                    if !selectedSubjects.contains(subject) { return false }
                } else {
                    // No lesson found, exclude if filtering by subject
                    return false
                }
            }

            // Search filter
            if !searchText.isEmpty {
                let titleText = title(for: la).lowercased()
                let query = searchText.lowercased()
                if !titleText.contains(query) { return false }
            }

            return true
        }
    }

    // Group assignments by day (start of day)
    func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    var groupedByDay: [(day: Date, items: [CDLessonAssignment])] {
        let dict = filteredAssignments
            .compactMap { la -> (Date, CDLessonAssignment)? in
                guard let presentedAt = la.presentedAt else { return nil }
                return (dayKey(presentedAt), la)
            }
            .reduce(into: [Date: [CDLessonAssignment]]()) { result, pair in
                result[pair.0, default: []].append(pair.1)
            }
            .mapValues { arr in
                // DEDUPLICATION: Ensure no duplicate IDs within each day group
                arr.uniqueByID.sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
            }
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }

    // Resolve title: prefer snapshot else lookup lesson by ID
    func title(for la: CDLessonAssignment) -> String {
        if let snap = la.lessonTitleSnapshot?.trimmed(), !snap.isEmpty {
            return snap
        }
        if let lid = la.lessonIDUUID, let t = lessonTitleCache[lid] {
            return LessonFormatter.titleOrFallback(t, fallback: "Lesson")
        }
        return "Lesson"
    }

    // CDStudent names or count string
    func studentNamesOrCount(for la: CDLessonAssignment) -> String {
        let ids = la.studentUUIDs
        let names: [String] = ids.compactMap { studentNameCache[$0] }
        if names.isEmpty { return "0 students" }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        } else {
            return "\(names.count) students"
        }
    }

    var body: some View {
        mainContent
            .searchable(text: $searchText)
            .sheet(item: $selectedAssignment) { la in
                LessonAssignmentDetailSheet(assignmentID: la.id ?? UUID()) {
                    selectedAssignment = nil
                }
            }
            .task {
                loadAssignments(limit: Self.initialLoadCount)
                if !hasBuiltCachesOnce {
                    await buildCachesAsync()
                    hasBuiltCachesOnce = true
                }
                // Initialize counts for change detection
                lastAssignmentCount = allAssignmentsForChangeDetection.count
                lastNotesCount = recentNotes.count
                lastLessonsCount = lessons.count
                lastStudentsCount = safeStudents.count
            }
            .onChange(of: allAssignmentsForChangeDetection.count) { _, newCount in
                // Only reload when count actually changes
                guard newCount != lastAssignmentCount else { return }
                lastAssignmentCount = newCount
                loadAssignments(limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
            }
            .onChange(of: recentNotes.count) { _, newCount in
                guard newCount != lastNotesCount else { return }
                lastNotesCount = newCount
                Task { await buildCachesAsync() }
            }
            .onChange(of: lessons.count) { _, newCount in
                guard newCount != lastLessonsCount else { return }
                lastLessonsCount = newCount
                Task { await buildCachesAsync() }
            }
            .onChange(of: safeStudents.count) { _, newCount in
                guard newCount != lastStudentsCount else { return }
                lastStudentsCount = newCount
                Task { await buildCachesAsync() }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            nameDisplayStyleRaw = NameDisplayStyle.firstLastInitial.rawValue
                        } label: {
                            HStack {
                                if nameDisplayStyle == .firstLastInitial {
                                    Image(systemName: "checkmark")
                                }
                                Text("First name + Last initial")
                            }
                        }
                        Button {
                            nameDisplayStyleRaw = NameDisplayStyle.initials.rawValue
                        } label: {
                            HStack {
                                if nameDisplayStyle == .initials {
                                    Image(systemName: "checkmark")
                                }
                                Text("Initials (AB)")
                            }
                        }
                    } label: {
                        Label("Names", systemImage: "textformat.abc")
                    }
                }
            }
    }
}

#Preview {
    LessonAssignmentHistoryView()
}
