// WorkDataMaintenance.swift
// Best-effort data maintenance helpers for WorkModel.
// Legacy WorkModel maintenance disabled.

import Foundation
import SwiftData

/// Non-critical maintenance utilities for keeping WorkModel data consistent.
/// These functions are idempotent and safe to call multiple times.
enum WorkDataMaintenance {
    static func backfillParticipantsIfNeeded(using context: ModelContext) {
        // Legacy WorkModel maintenance disabled.
    }

    static func migrateWorksToContractsIfNeeded(using context: ModelContext) {
        // Legacy migration disabled; mark as done to avoid reruns.
        let flagKey = "Migration.workToContracts.v1"
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}

