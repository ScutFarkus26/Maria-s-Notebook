// BandwidthThrottler.swift
// Provides bandwidth throttling for cloud uploads

import Foundation

/// Provides bandwidth throttling for backup uploads.
/// Allows limiting upload speed to avoid saturating network connections.
public actor BandwidthThrottler {

    // MARK: - Types

    /// Bandwidth limit presets
    public enum BandwidthPreset: String, CaseIterable, Identifiable, Sendable {
        case unlimited = "Unlimited"
        case highSpeed = "High Speed (10 MB/s)"
        case mediumSpeed = "Medium Speed (5 MB/s)"
        case lowSpeed = "Low Speed (1 MB/s)"
        case minimal = "Minimal (500 KB/s)"

        public var id: String { rawValue }

        /// Bytes per second limit (0 = unlimited)
        public var bytesPerSecond: Int {
            switch self {
            case .unlimited: return 0
            case .highSpeed: return 10 * 1024 * 1024  // 10 MB/s
            case .mediumSpeed: return 5 * 1024 * 1024 // 5 MB/s
            case .lowSpeed: return 1 * 1024 * 1024    // 1 MB/s
            case .minimal: return 500 * 1024          // 500 KB/s
            }
        }
    }

    /// Statistics about throttled transfer
    public struct TransferStats: Sendable {
        public let totalBytes: Int64
        public let elapsedTime: TimeInterval
        public let averageSpeed: Double // bytes per second
        public let peakSpeed: Double
        public let throttledTime: TimeInterval

        public var formattedAverageSpeed: String {
            formatSpeed(averageSpeed)
        }

        public var formattedPeakSpeed: String {
            formatSpeed(peakSpeed)
        }

        private func formatSpeed(_ speed: Double) -> String {
            if speed >= 1024 * 1024 {
                return String(format: "%.1f MB/s", speed / (1024 * 1024))
            } else if speed >= 1024 {
                return String(format: "%.1f KB/s", speed / 1024)
            } else {
                return String(format: "%.0f B/s", speed)
            }
        }
    }

    // MARK: - Properties

    /// Current bandwidth limit in bytes per second (0 = unlimited)
    private var limitBytesPerSecond: Int

    /// Token bucket for rate limiting
    private var tokens: Double = 0
    private var lastTokenRefill: Date = Date()

    /// Statistics tracking
    private var totalBytesTransferred: Int64 = 0
    private var transferStartTime: Date?
    private var peakSpeed: Double = 0
    private var totalThrottledTime: TimeInterval = 0

    /// Chunk size for transfers
    private let defaultChunkSize: Int = 64 * 1024 // 64 KB

    // MARK: - Initialization

    public init(bytesPerSecond: Int = 0) {
        self.limitBytesPerSecond = bytesPerSecond
        self.tokens = Double(bytesPerSecond)
    }

    public init(preset: BandwidthPreset) {
        self.limitBytesPerSecond = preset.bytesPerSecond
        self.tokens = Double(preset.bytesPerSecond)
    }

    // MARK: - Configuration

    /// Sets the bandwidth limit.
    /// - Parameter bytesPerSecond: Maximum bytes per second (0 = unlimited)
    public func setLimit(bytesPerSecond: Int) {
        limitBytesPerSecond = bytesPerSecond
        tokens = Double(bytesPerSecond)
        lastTokenRefill = Date()
    }

    /// Sets the bandwidth limit using a preset.
    public func setLimit(preset: BandwidthPreset) {
        setLimit(bytesPerSecond: preset.bytesPerSecond)
    }

    /// Gets the current limit in bytes per second.
    public func getLimit() -> Int {
        limitBytesPerSecond
    }

    // MARK: - Throttling

    /// Requests permission to transfer a number of bytes.
    /// Waits if necessary to comply with rate limit.
    ///
    /// - Parameter bytes: Number of bytes to transfer
    /// - Returns: The number of bytes actually permitted (may be less than requested)
    public func requestTransfer(bytes: Int) async throws -> Int {
        // No limit - allow full transfer
        if limitBytesPerSecond == 0 {
            trackTransfer(bytes: bytes)
            return bytes
        }

        // Refill tokens based on elapsed time
        refillTokens()

        // Calculate how many bytes we can transfer now
        let availableBytes = min(bytes, Int(tokens))

        if availableBytes > 0 {
            tokens -= Double(availableBytes)
            trackTransfer(bytes: availableBytes)
            return availableBytes
        }

        // Need to wait for tokens
        let bytesNeeded = Double(min(bytes, defaultChunkSize))
        let tokensNeeded = bytesNeeded - tokens
        let waitTime = tokensNeeded / Double(limitBytesPerSecond)

        if waitTime > 0 {
            totalThrottledTime += waitTime
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        // Refill after waiting
        refillTokens()

        let nowAvailable = min(bytes, Int(tokens))
        if nowAvailable > 0 {
            tokens -= Double(nowAvailable)
            trackTransfer(bytes: nowAvailable)
            return nowAvailable
        }

        return 0
    }

    /// Transfers data with throttling applied.
    ///
    /// - Parameters:
    ///   - data: Data to transfer
    ///   - chunkHandler: Handler called for each chunk with (offset, chunk data)
    /// - Returns: Transfer statistics
    public func transferWithThrottling(
        data: Data,
        chunkHandler: @escaping (Int, Data) async throws -> Void
    ) async throws -> TransferStats {
        resetStats()
        transferStartTime = Date()

        var offset = 0
        while offset < data.count {
            let remaining = data.count - offset
            let requestSize = min(remaining, defaultChunkSize)

            let permitted = try await requestTransfer(bytes: requestSize)
            if permitted > 0 {
                let chunk = data[offset..<(offset + permitted)]
                try await chunkHandler(offset, Data(chunk))
                offset += permitted
            }
        }

        return getStats()
    }

    /// Gets current transfer statistics.
    public func getStats() -> TransferStats {
        let elapsed = transferStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let avgSpeed = elapsed > 0 ? Double(totalBytesTransferred) / elapsed : 0

        return TransferStats(
            totalBytes: totalBytesTransferred,
            elapsedTime: elapsed,
            averageSpeed: avgSpeed,
            peakSpeed: peakSpeed,
            throttledTime: totalThrottledTime
        )
    }

    /// Resets transfer statistics.
    public func resetStats() {
        totalBytesTransferred = 0
        transferStartTime = nil
        peakSpeed = 0
        totalThrottledTime = 0
    }

    // MARK: - Private Helpers

    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTokenRefill)
        let newTokens = elapsed * Double(limitBytesPerSecond)

        // Cap tokens at 1 second worth (burst limit)
        tokens = min(tokens + newTokens, Double(limitBytesPerSecond))
        lastTokenRefill = now
    }

    private func trackTransfer(bytes: Int) {
        totalBytesTransferred += Int64(bytes)

        // Track peak speed (instantaneous)
        if let start = transferStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                let currentSpeed = Double(totalBytesTransferred) / elapsed
                peakSpeed = max(peakSpeed, currentSpeed)
            }
        } else {
            transferStartTime = Date()
        }
    }
}

// MARK: - ThrottledCloudUploader

/// Helper for uploading files with bandwidth throttling.
@MainActor
public final class ThrottledCloudUploader {

    private let throttler: BandwidthThrottler
    private let fileManager = FileManager.default

    public init(preset: BandwidthThrottler.BandwidthPreset = .unlimited) {
        self.throttler = BandwidthThrottler(preset: preset)
    }

    /// Sets the bandwidth limit.
    public func setLimit(preset: BandwidthThrottler.BandwidthPreset) async {
        await throttler.setLimit(preset: preset)
    }

    /// Uploads a file with throttling applied.
    ///
    /// - Parameters:
    ///   - sourceURL: Local file to upload
    ///   - destinationURL: Remote destination (iCloud, etc.)
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Transfer statistics
    public func uploadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> BandwidthThrottler.TransferStats {
        let data = try Data(contentsOf: sourceURL)
        let totalSize = Double(data.count)

        // For iCloud, we write the full file but track the "throttled" transfer
        // This provides feedback even though actual iCloud upload is handled by the system
        let stats = try await throttler.transferWithThrottling(data: data) { offset, chunk in
            // Report progress
            let currentProgress = Double(offset + chunk.count) / totalSize
            await MainActor.run {
                progress(currentProgress)
            }
        }

        // Actually copy the file (the throttling above is just for user feedback)
        // Real iCloud upload is handled by the system after the file is in the container
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return stats
    }

    /// Gets current transfer statistics.
    public func getStats() async -> BandwidthThrottler.TransferStats {
        await throttler.getStats()
    }
}
