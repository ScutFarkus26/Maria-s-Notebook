// CloudBackupConfiguration.swift
// Configuration types for CloudBackupService

import Foundation

/// Configuration for retry logic
public struct RetryConfiguration: Sendable {
    public var maxRetries: Int
    public var baseDelaySeconds: Double
    public var maxDelaySeconds: Double
    public var backoffMultiplier: Double

    public static let `default` = RetryConfiguration(
        maxRetries: 3,
        baseDelaySeconds: 1.0,
        maxDelaySeconds: 30.0,
        backoffMultiplier: 2.0
    )

    public init(maxRetries: Int, baseDelaySeconds: Double, maxDelaySeconds: Double, backoffMultiplier: Double) {
        self.maxRetries = maxRetries
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.backoffMultiplier = backoffMultiplier
    }
}

/// Configuration for scheduled cloud backups
public struct ScheduleConfiguration: Codable, Sendable {
    public var enabled: Bool
    public var intervalHours: Int
    public var retentionCount: Int

    public static let `default` = ScheduleConfiguration(
        enabled: false,
        intervalHours: 24,
        retentionCount: 7
    )

    public init(enabled: Bool, intervalHours: Int, retentionCount: Int) {
        self.enabled = enabled
        self.intervalHours = intervalHours
        self.retentionCount = retentionCount
    }
}
