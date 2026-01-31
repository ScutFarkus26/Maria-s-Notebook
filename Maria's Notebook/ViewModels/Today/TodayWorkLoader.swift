// TodayWorkLoader.swift
// Loader for processing work items for the Today view.
// Encapsulates the work loading and schedule building logic used by TodayViewModel.

import Foundation
import SwiftData

// MARK: - Today Work Loader

/// Loader for processing work items for the Today view.
enum TodayWorkLoader {

    // MARK: - Types

    /// Result of loading and processing work.
    struct WorkLoadResult {
        let overdueSchedule: [ScheduledWorkItem]
        let todaysSchedule: [ScheduledWorkItem]
        let staleFollowUps: [FollowUpWorkItem]
        let workByID: [UUID: WorkModel]
        let neededStudentIDs: Set<UUID>
        let neededLessonIDs: Set<UUID>
    }

    /// Empty result for when no data is found.
    static var emptyResult: WorkLoadResult {
        WorkLoadResult(
            overdueSchedule: [],
            todaysSchedule: [],
            staleFollowUps: [],
            workByID: [:],
            neededStudentIDs: [],
            neededLessonIDs: []
        )
    }

    // MARK: - Load Work

    /// Fetches and processes work items for a day.
    /// - Parameters:
    ///   - day: Start of the day
    ///   - nextDay: Start of the next day
    ///   - referenceDate: The reference date for schedule calculations
    ///   - studentsByID: Cached students for level filtering
    ///   - levelFilter: The level filter to apply
    ///   - context: Model context for fetching and schedule building
    /// - Returns: Processed work result with schedules and IDs needed for caching
    static func loadWork(
        day: Date,
        nextDay: Date,
        referenceDate: Date,
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter,
        context: ModelContext
    ) -> WorkLoadResult {
        guard let fetchResult = TodayDataFetcher.fetchWorkData(
            day: day,
            nextDay: nextDay,
            referenceDate: referenceDate,
            context: context
        ) else {
            return emptyResult
        }

        // Build work lookup
        let workByID = fetchResult.workItems.toDictionary(by: \.id)

        // Build schedule using TodayScheduleBuilder
        let schedule = TodayScheduleBuilder.buildSchedule(
            workItems: fetchResult.workItems,
            planItemsByWork: fetchResult.planItemsByWork,
            notesByWork: fetchResult.notesByWork,
            studentsByID: studentsByID,
            levelFilter: levelFilter,
            referenceDate: referenceDate,
            modelContext: context
        )

        return WorkLoadResult(
            overdueSchedule: schedule.overdue,
            todaysSchedule: schedule.today,
            staleFollowUps: schedule.stale,
            workByID: workByID,
            neededStudentIDs: fetchResult.neededStudentIDs,
            neededLessonIDs: fetchResult.neededLessonIDs
        )
    }

    // MARK: - Load Completed Work

    /// Result of loading completed work.
    struct CompletedWorkResult {
        let completedWork: [WorkModel]
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
        context: ModelContext
    ) -> CompletedWorkResult {
        let workItems = TodayDataFetcher.fetchCompletedWork(day: day, nextDay: nextDay, context: context)

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
