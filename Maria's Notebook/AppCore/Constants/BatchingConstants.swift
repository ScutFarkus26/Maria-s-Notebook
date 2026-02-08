enum BatchingConstants {
    /// Default batch size for fetching entities from SwiftData
    static let defaultBatchSize = 1000

    /// Maximum number of days to iterate (safety limit ~100 years)
    static let maxDaysToIterate = 36500

    /// Default entity count threshold for large dataset warnings
    static let largeDatasetThreshold = 10000

    /// Estimated bytes per entity for size calculations
    static let estimatedBytesPerEntity = 1000
}
