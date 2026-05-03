// WorkCycleViewModel.swift
// ViewModel for the Work Cycle Tracker — manages session lifecycle, timer, and student grid.

import SwiftUI
import CoreData

@Observable @MainActor
final class WorkCycleViewModel {
    private(set) var session: CDWorkCycleSession?
    private(set) var studentCards: [StudentCycleCard] = []
    private(set) var entries: [CDWorkCycleEntry] = []
    private(set) var isLoading = false
    private(set) var cycleSummary: CycleSummary?
    private(set) var pastSessions: [CDWorkCycleSession] = []

    var searchText: String = ""
    var levelFilter: LevelFilter = .all

    /// Elapsed seconds at the moment the session was last resumed (or 0 for a fresh session).
    /// Combined with `liveTickReference` to compute current elapsed without a timer.
    @ObservationIgnored
    private var resumeBaselineElapsed: TimeInterval = 0

    /// When the session was last resumed/started. `nil` when paused or no session — in that
    /// case `resumeBaselineElapsed` is the frozen value to display.
    @ObservationIgnored
    private var liveTickReference: Date?

    // MARK: - Filtered Cards

    var filteredCards: [StudentCycleCard] {
        var cards = studentCards

        if levelFilter != .all {
            cards = cards.filter { levelFilter.matches($0.level) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query) ||
                ($0.nickname?.lowercased().contains(query) ?? false)
            }
        }

        return cards
    }

    var hasActiveSession: Bool {
        guard let session else { return false }
        return !session.isCompleted
    }

    // MARK: - Timer Display

    /// Computes elapsed seconds for the active session at a given moment.
    /// Use a 1Hz `TimelineView` to drive this for live display — no view-model timer needed.
    func elapsedTime(at date: Date) -> TimeInterval {
        guard let liveTickReference else { return resumeBaselineElapsed }
        return resumeBaselineElapsed + date.timeIntervalSince(liveTickReference)
    }

    func elapsedFormatted(at date: Date) -> String {
        let total = Int(elapsedTime(at: date))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Load Data

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        loadStudents(context: context)
        loadExistingSession(context: context)
        loadPastSessions(context: context)
    }

    func loadStudents(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        request.sortDescriptors = CDStudent.sortByName
        let allStudents = TestStudentsFilter.filterVisible(context.safeFetch(request))

        // Build student cards with current entry data
        let entriesByStudent = Dictionary(grouping: entries) { $0.studentID }

        studentCards = allStudents.compactMap { student in
            guard let sid = student.id else { return nil }
            let sidStr = sid.uuidString
            let studentEntries = entriesByStudent[sidStr] ?? []
            let latestEntry = studentEntries
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                .first

            return StudentCycleCard(
                id: sid,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                currentActivity: latestEntry?.activityDescription.isEmpty == false
                    ? latestEntry?.activityDescription : nil,
                socialMode: latestEntry?.socialMode,
                concentration: latestEntry?.concentration,
                entryCount: studentEntries.count
            )
        }
    }

    func loadExistingSession(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDWorkCycleSession.self)
        request.predicate = NSPredicate(
            format: "statusRaw IN %@",
            [CycleStatus.active.rawValue, CycleStatus.paused.rawValue]
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCycleSession.startTime, ascending: false)]
        request.fetchLimit = 1

        if let existing = context.safeFetch(request).first {
            session = existing
            loadEntries(for: existing, context: context)

            // Restore elapsed-time state matching prior in-app behavior:
            // active sessions tick live from startTime; paused sessions show now-since-start
            // as a frozen snapshot (preserving the existing reload-jump behavior).
            let elapsedNow = existing.startTime.map { Date().timeIntervalSince($0) } ?? 0
            if existing.isActive {
                resumeBaselineElapsed = 0
                liveTickReference = existing.startTime
            } else {
                resumeBaselineElapsed = elapsedNow
                liveTickReference = nil
            }
        }
    }

    private func loadPastSessions(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDWorkCycleSession.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@",
            CycleStatus.completed.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCycleSession.date, ascending: false)]
        request.fetchLimit = 10
        pastSessions = context.safeFetch(request)
    }

    private func loadEntries(for session: CDWorkCycleSession, context: NSManagedObjectContext) {
        guard let sid = session.id else { return }
        let request = CDFetchRequest(CDWorkCycleEntry.self)
        request.predicate = NSPredicate(format: "sessionID == %@", sid.uuidString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCycleEntry.createdAt, ascending: false)]
        entries = context.safeFetch(request)
    }

    // MARK: - Session Lifecycle

    func startNewSession(context: NSManagedObjectContext) {
        let newSession = CDWorkCycleSession(context: context)
        session = newSession
        entries = []
        resumeBaselineElapsed = 0
        liveTickReference = newSession.startTime
        cycleSummary = nil
        context.safeSave()
        loadStudents(context: context)
    }

    func pauseSession(context: NSManagedObjectContext) {
        guard let session else { return }
        // Freeze the current elapsed value before tearing down the live reference.
        resumeBaselineElapsed = elapsedTime(at: Date())
        liveTickReference = nil
        session.status = .paused
        context.safeSave()
    }

    func resumeSession(context: NSManagedObjectContext) {
        guard let session else { return }
        liveTickReference = Date()
        session.status = .active
        context.safeSave()
    }

    func endSession(context: NSManagedObjectContext) {
        guard let session else { return }
        // Snapshot final elapsed value so computeSummary's fallback stays correct.
        resumeBaselineElapsed = elapsedTime(at: Date())
        liveTickReference = nil
        session.endTime = Date()
        session.status = .completed
        context.safeSave()
        computeSummary()
    }

    // MARK: - Entry Management

    func addEntry(
        studentID: UUID,
        activity: String,
        socialMode: SocialMode,
        concentration: ConcentrationLevel,
        workItemID: UUID?,
        context: NSManagedObjectContext
    ) {
        guard let session, let sessionID = session.id else { return }

        let entry = CDWorkCycleEntry(context: context)
        entry.sessionID = sessionID.uuidString
        entry.studentID = studentID.uuidString
        entry.activityDescription = activity
        entry.socialMode = socialMode
        entry.concentration = concentration
        entry.workItemID = workItemID?.uuidString
        context.safeSave()

        loadEntries(for: session, context: context)
        loadStudents(context: context)
    }

    func updateEntry(_ entry: CDWorkCycleEntry, context: NSManagedObjectContext) {
        entry.modifiedAt = Date()
        context.safeSave()

        if let session {
            loadEntries(for: session, context: context)
            loadStudents(context: context)
        }
    }

    // MARK: - Summary

    func computeSummary() {
        let duration = session?.duration ?? elapsedTime(at: Date())

        var concentrationCounts: [ConcentrationLevel: Int] = [:]
        var socialModeCounts: [SocialMode: Int] = [:]
        var trackedStudents: Set<String> = []

        for entry in entries {
            concentrationCounts[entry.concentration, default: 0] += 1
            socialModeCounts[entry.socialMode, default: 0] += 1
            trackedStudents.insert(entry.studentID)
        }

        cycleSummary = CycleSummary(
            duration: duration,
            totalEntries: entries.count,
            studentsTracked: trackedStudents.count,
            concentrationBreakdown: concentrationCounts,
            socialModeBreakdown: socialModeCounts
        )
    }
}
