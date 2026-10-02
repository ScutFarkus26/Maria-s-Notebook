// TodayWorkLoader.swift
// Loader for processing work items for the Today view.
// Encapsulates the work loading and schedule building logic used by TodayViewModel.

import Foundation
import CoreData

// MARK: - Today Work Loader

/// Loader for processing work items for the Today view.
enum TodayWorkLoader {

    // MARK: - Types

    /// Result of loading and processing work.
    struct WorkLoadResult {
        let staleFollowUps: [FollowUpWorkItem]
        /// Every stale work item, before `staleFollowUps` keeps the top rows.
        let staleTotalCount: Int
        let workByID: [UUID: CDWorkModel]
        let neededStudentIDs: Set<UUID>
        let neededLessonIDs: Set<UUID>
    }

    /// Empty result for when no data is found.
    static var emptyResult: WorkLoadResult {
        WorkLoadResult(
            staleFollowUps: [],
            staleTotalCount: 0,
            workByID: [:],
            neededStudentIDs: [],
            neededLessonIDs: []
        )
    }

    // MARK: - Load Work

    // Processes the open work `reload()` already fetched for a day. It used to
    // run `TodayDataFetcher.fetchWorkData` a second time (three more fetches
    // per reload) for the same rows.
    // - Parameters:
    //   - fetchResult: `TodayDataFetcher.fetchWorkData` for the day (nil = the fetch failed)
    //   - referenceDate: The reference date for schedule calculations
    //   - studentsByID: Cached students for level filtering
    //   - levelFilter: The level filter to apply
    //   - context: Model context for schedule building
    // - Returns: Processed work result with schedules and IDs needed for caching
    static func loadWork(
        from fetchResult: TodayDataFetcher.WorkFetchResult?,
        referenceDate: Date,
        studentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter,
        context: NSManagedObjectContext
    ) -> WorkLoadResult {
        guard let fetchResult else { return emptyResult }

        // Build work lookup
        let workByID: [UUID: CDWorkModel] = fetchResult.workItems.reduce(into: [:]) { dict, work in
            guard let id = work.id else { return }
            dict[id] = work
        }

        // Build schedule using TodayScheduleBuilder
        let schedule = TodayScheduleBuilder.buildSchedule(
            workItems: fetchResult.workItems,
            checkInsByWork: fetchResult.checkInsByWork,
            notesByWork: fetchResult.notesByWork,
            studentsByID: studentsByID,
            levelFilter: levelFilter,
            referenceDate: referenceDate,
            context: context
        )

        return WorkLoadResult(
            staleFollowUps: schedule.stale,
            staleTotalCount: schedule.staleTotalCount,
            workByID: workByID,
            neededStudentIDs: fetchResult.neededStudentIDs,
            neededLessonIDs: fetchResult.neededLessonIDs
        )
    }

    // MARK: - Load Completed Work

    /// Result of loading completed work.
    struct CompletedWorkResult {
        let completedWork: [CDWorkModel]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches completed work items for a day.
    /// - Parameters:
    ///   - day: Start of the day
    ///   - nextDay: Start of the next day
    ///   - context: Model context for fetching
    /// - Returns: Completed work and student IDs needed for caching
    static func fetchCompletedWork(
        day: Date,
        nextDay: Date,
        context: NSManagedObjectContext,
        errorCollector: FetchErrorCollector? = nil
    ) -> CompletedWorkResult {
        let workItems = TodayDataFetcher.fetchCompletedWork(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )

        // Collect student IDs for completed work
        var neededStudentIDs = Set<UUID>()
        for work in workItems {
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
        }

        return CompletedWorkResult(
            completedWork: workItems,
            neededStudentIDs: neededStudentIDs
        )
    }
}
