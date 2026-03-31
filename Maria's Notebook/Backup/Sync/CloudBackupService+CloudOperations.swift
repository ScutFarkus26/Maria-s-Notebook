// CloudBackupService+CloudOperations.swift
// iCloud listing and download operations

import Foundation
import OSLog

/// Thread-safe single-resumption guard for checked continuations.
private actor SingleResumptionTracker {
    var hasResumed = false

    func tryResume(with result: Result<URL, Error>) -> Bool {
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

extension CloudBackupService {

    // MARK: - Listing

    /// Lists all backups available in iCloud Drive
    /// - Returns: Array of cloud backup info sorted by date (newest first)
    public func listCloudBackups() async throws -> [CloudBackupInfo] {
        let cloudDir = try requireCloudDirectory()

        // Ensure directory exists
        if !fileManager.fileExists(atPath: cloudDir.path) {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemIsDownloadingKey
        ]

        let enumerator = fileManager.enumerator(
            at: cloudDir,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        guard let enumerator else {
            return []
        }

        // Collect URLs first to avoid makeIterator() in async context (Swift 6 requirement)
        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }

        let backups = fileURLs.compactMap { fileURL -> CloudBackupInfo? in
            guard fileURL.pathExtension == BackupFile.fileExtension else { return nil }
            return cloudBackupInfo(from: fileURL, resourceKeys: resourceKeys)
        }

        // Sort by modification date (newest first)
        return backups.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Downloading

    /// Downloads a backup from iCloud if not already downloaded
    /// - Parameter backup: The backup to download
    /// - Returns: The local URL once downloaded
    public func downloadBackupIfNeeded(_ backup: CloudBackupInfo) async throws -> URL {
        try requireICloudAvailable()

        if backup.isDownloaded {
            return backup.fileURL
        }

        // Start download
        try fileManager.startDownloadingUbiquitousItem(at: backup.fileURL)

        // Use NSFileCoordinator to wait for the file to be available
        // Modernized using structured concurrency with timeout support
        let timeoutError = cloudDownloadError("Download timed out for '\(backup.fileName)'", code: 408)
        let noResultError = cloudDownloadError("No task result available", code: 500)
        return try await withThrowingTaskGroup(of: URL.self) { group in
            // Add the file coordination task
            group.addTask {
                try await self.coordinateDownload(for: backup)
            }

            // Add timeout task using structured concurrency
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw timeoutError
            }

            // Return the first result (either success or timeout)
            guard let result = try await group.next() else {
                throw noResultError
            }
            group.cancelAll() // Cancel the other task
            return result
        }
    }

    // MARK: - Private Helpers

    /// Builds a `CloudBackupInfo` from a file URL, returning nil on failure.
    private func cloudBackupInfo(
        from fileURL: URL,
        resourceKeys: Set<URLResourceKey>
    ) -> CloudBackupInfo? {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
        } catch {
            let name = fileURL.lastPathComponent
            let desc = error.localizedDescription
            Self.logger.warning("CDResource values failed for \(name, privacy: .public): \(desc, privacy: .public)")
            return nil
        }

        // Check download status using the downloading status key
        let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus
        let isDownloaded = downloadStatus == .current || downloadStatus == nil

        return CloudBackupInfo(
            id: UUID(),
            fileName: resourceValues.name ?? fileURL.lastPathComponent,
            fileURL: fileURL,
            fileSize: Int64(resourceValues.fileSize ?? 0),
            createdAt: resourceValues.creationDate ?? Date.distantPast,
            modifiedAt: resourceValues.contentModificationDate ?? Date.distantPast,
            isDownloaded: isDownloaded,
            isUploading: resourceValues.ubiquitousItemIsUploading ?? false,
            isDownloading: resourceValues.ubiquitousItemIsDownloading ?? false
        )
    }

    /// Coordinates reading a ubiquitous file, waiting for it to finish downloading.
    private func coordinateDownload(for backup: CloudBackupInfo) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            Task.detached(priority: .userInitiated) {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?

                let tracker = SingleResumptionTracker()

                coordinator.coordinate(
                    readingItemAt: backup.fileURL,
                    options: [.withoutChanges],
                    error: &coordinatorError
                ) { url in
                    self.handleCoordinatedRead(
                        url: url, backup: backup, tracker: tracker, continuation: continuation
                    )
                }

                if let error = coordinatorError {
                    Task {
                        let wrappedErr = BackupOperationError.cloudOperationFailed(
                            .downloadFailed(underlying: error)
                        )
                        if await tracker.tryResume(with: .failure(wrappedErr)) {
                            continuation.resume(throwing: wrappedErr)
                        }
                    }
                }
            }
        }
    }

    private func handleCoordinatedRead(
        url: URL,
        backup: CloudBackupInfo,
        tracker: SingleResumptionTracker,
        continuation: CheckedContinuation<URL, Error>
    ) {
        Task { @MainActor in
            do {
                let resourceValues = try url.resourceValues(
                    forKeys: [.ubiquitousItemDownloadingStatusKey]
                )
                if resourceValues.ubiquitousItemDownloadingStatus == .current ||
                   resourceValues.ubiquitousItemDownloadingStatus == nil {
                    if await tracker.tryResume(with: .success(url)) {
                        continuation.resume(returning: url)
                    }
                } else {
                    let error = self.cloudDownloadError(
                        "File '\(backup.fileName)' not downloaded", code: 404
                    )
                    if await tracker.tryResume(with: .failure(error)) {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                let wrappedError = BackupOperationError.cloudOperationFailed(
                    .downloadFailed(underlying: error)
                )
                if await tracker.tryResume(with: .failure(wrappedError)) {
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    /// Creates a consistent cloud download error.
    func cloudDownloadError(_ message: String, code: Int) -> BackupOperationError {
        let nsError = NSError(
            domain: "CloudBackup",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        return BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: nsError))
    }
}
