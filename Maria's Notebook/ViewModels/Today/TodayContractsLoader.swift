// TodayContractsLoader.swift
// Loader for processing work contracts for the Today view.
// Encapsulates the contracts loading and schedule building logic used by TodayViewModel.

import Foundation
import SwiftData

// MARK: - Today Contracts Loader

/// Loader for processing work contracts for the Today view.
enum TodayContractsLoader {

    // MARK: - Types

    /// Result of loading and processing contracts.
    struct ContractsResult {
        let overdueSchedule: [ContractScheduleItem]
        let todaysSchedule: [ContractScheduleItem]
        let staleFollowUps: [ContractFollowUpItem]
        let workByID: [UUID: WorkModel]
        let neededStudentIDs: Set<UUID>
        let neededLessonIDs: Set<UUID>
    }

    /// Empty result for when no data is found.
    static var emptyResult: ContractsResult {
        ContractsResult(
            overdueSchedule: [],
            todaysSchedule: [],
            staleFollowUps: [],
            workByID: [:],
            neededStudentIDs: [],
            neededLessonIDs: []
        )
    }

    // MARK: - Load Contracts

    /// Fetches and processes work contracts for a day.
    /// - Parameters:
    ///   - day: Start of the day
    ///   - nextDay: Start of the next day
    ///   - referenceDate: The reference date for schedule calculations
    ///   - studentsByID: Cached students for level filtering
    ///   - levelFilter: The level filter to apply
    ///   - context: Model context for fetching and schedule building
    /// - Returns: Processed contracts result with schedules and IDs needed for caching
    static func loadContracts(
        day: Date,
        nextDay: Date,
        referenceDate: Date,
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter,
        context: ModelContext
    ) -> ContractsResult {
        guard let fetchResult = TodayDataFetcher.fetchWorkData(
            day: day,
            nextDay: nextDay,
            referenceDate: referenceDate,
            context: context
        ) else {
            return emptyResult
        }

        // Build work lookup
        let workByID = Dictionary(uniqueKeysWithValues: fetchResult.workItems.map { ($0.id, $0) })

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

        return ContractsResult(
            overdueSchedule: schedule.overdue,
            todaysSchedule: schedule.today,
            staleFollowUps: schedule.stale,
            workByID: workByID,
            neededStudentIDs: fetchResult.neededStudentIDs,
            neededLessonIDs: fetchResult.neededLessonIDs
        )
    }

    // MARK: - Load Completed Contracts

    /// Result of loading completed contracts.
    struct CompletedContractsResult {
        let completedContracts: [WorkModel]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches completed work items for a day.
    /// - Parameters:
    ///   - day: Start of the day
    ///   - nextDay: Start of the next day
    ///   - context: Model context for fetching
    /// - Returns: Completed contracts and student IDs needed for caching
    static func fetchCompletedContracts(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> CompletedContractsResult {
        let workItems = TodayDataFetcher.fetchCompletedWork(day: day, nextDay: nextDay, context: context)

        // Collect student IDs for completed work
        var neededStudentIDs = Set<UUID>()
        for work in workItems {
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
        }

        return CompletedContractsResult(
            completedContracts: workItems,
            neededStudentIDs: neededStudentIDs
        )
    }
}
