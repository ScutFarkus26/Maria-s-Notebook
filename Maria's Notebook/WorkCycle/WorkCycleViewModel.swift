// WorkCycleViewModel.swift
// ViewModel for the Work Cycle Tracker — manages session lifecycle, timer, and student grid.

import SwiftUI
import CoreData

@Observable @MainActor
final class WorkCycleViewModel {
    private(set) var session: CDWorkCycleSession?
    private(set) var studentCards: [StudentCycleCard] = []
    private(set) var entries: [CDWorkCycleEntry] = []
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var isLoading = false
    private(set) var cycleSummary: CycleSummary?
    private(set) var pastSessions: [CDWorkCycleSession] = []

    var searchText: String = ""
    var levelFilter: LevelFilter = .all

    private var timerTask: Task<Void, Never>?

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

    var hasActiveSession: Bool { session != nil && session?.isCompleted == false }

    // MARK: - Timer Display

    var elapsedFormatted: String {
        let total = Int(elapsedTime)
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

            // Resume elapsed time
            if let start = existing.startTime {
                elapsedTime = Date().timeIntervalSince(start)
            }

            // Resume timer if active
            if existing.isActive {
                startTimer()
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
        elapsedTime = 0
        cycleSummary = nil
        context.safeSave()
        startTimer()
        loadStudents(context: context)
    }

    func pauseSession(context: NSManagedObjectContext) {
        guard let session else { return }
        session.status = .paused
        context.safeSave()
        stopTimer()
    }

    func resumeSession(context: NSManagedObjectContext) {
        guard let session else { return }
        session.status = .active
        context.safeSave()
        startTimer()
    }

    func endSession(context: NSManagedObjectContext) {
        guard let session else { return }
        session.endTime = Date()
        session.status = .completed
        context.safeSave()
        stopTimer()
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

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.elapsedTime += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Summary

    func computeSummary() {
        let duration = session?.duration ?? elapsedTime

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
