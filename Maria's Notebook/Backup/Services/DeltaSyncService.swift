import Foundation
import CryptoKit

/// Handles delta synchronization for cloud backups using binary diffs
/// Only uploads changed portions of backups to minimize bandwidth usage
@MainActor
public final class DeltaSyncService {
    
    // MARK: - Types
    
    public struct DeltaChunk: Codable {
        public let offset: Int
        public let length: Int
        public let data: Data
        public let checksum: String
    }
    
    public struct DeltaManifest: Codable {
        public let baseFileChecksum: String
        public let targetFileChecksum: String
        public let chunks: [DeltaChunk]
        public let totalOriginalSize: Int
        public let totalDeltaSize: Int
        public let compressionRatio: Double
        public let createdAt: Date
        
        public var savedBytes: Int {
            totalOriginalSize - totalDeltaSize
        }
        
        public var savingsPercentage: Double {
            guard totalOriginalSize > 0 else { return 0 }
            return Double(savedBytes) / Double(totalOriginalSize) * 100.0
        }
    }
    
    public struct SyncResult {
        public let manifest: DeltaManifest
        public let uploadedChunks: Int
        public let totalChunks: Int
        public let bytesUploaded: Int
        public let bytesSaved: Int
        public let duration: TimeInterval
    }
    
    // MARK: - Configuration
    
    public struct Configuration {
        public var chunkSize: Int = 64 * 1024  // 64KB chunks
        public var compressionEnabled: Bool = true
        public var checksumValidation: Bool = true
        
        public static let `default` = Configuration()
    }
    
    private let configuration: Configuration
    private let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Delta Generation
    
    /// Generates a delta between two backup files
    /// - Parameters:
    ///   - baseURL: The original/reference backup file
    ///   - targetURL: The new backup file to compare
    /// - Returns: Delta manifest describing the differences
    public func generateDelta(
        from baseURL: URL,
        to targetURL: URL
    ) async throws -> DeltaManifest {
        
        let baseData = try Data(contentsOf: baseURL)
        let targetData = try Data(contentsOf: targetURL)
        
        // Generate checksums
        let baseChecksum = sha256(baseData)
        let targetChecksum = sha256(targetData)
        
        // If files are identical, return empty delta
        if baseChecksum == targetChecksum {
            return DeltaManifest(
                baseFileChecksum: baseChecksum,
                targetFileChecksum: targetChecksum,
                chunks: [],
                totalOriginalSize: targetData.count,
                totalDeltaSize: 0,
                compressionRatio: 1.0,
                createdAt: Date()
            )
        }
        
        // Generate binary diff using rolling hash
        let chunks = try generateDeltaChunks(base: baseData, target: targetData)
        
        let deltaSize = chunks.reduce(0) { $0 + $1.data.count }
        let compressionRatio = targetData.count > 0 ? Double(deltaSize) / Double(targetData.count) : 0.0
        
        return DeltaManifest(
            baseFileChecksum: baseChecksum,
            targetFileChecksum: targetChecksum,
            chunks: chunks,
            totalOriginalSize: targetData.count,
            totalDeltaSize: deltaSize,
            compressionRatio: compressionRatio,
            createdAt: Date()
        )
    }
    
    /// Applies a delta to reconstruct the target file
    /// - Parameters:
    ///   - manifest: The delta manifest
    ///   - baseURL: The base file to apply delta to
    ///   - outputURL: Where to write the reconstructed file
    public func applyDelta(
        manifest: DeltaManifest,
        to baseURL: URL,
        outputURL: URL
    ) async throws {
        
        let baseData = try Data(contentsOf: baseURL)
        
        // Verify base file checksum
        let baseChecksum = sha256(baseData)
        guard baseChecksum == manifest.baseFileChecksum else {
            throw NSError(
                domain: "DeltaSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Base file checksum mismatch"]
            )
        }
        
        // Start with base data
        var reconstructed = baseData
        
        // Apply each chunk
        for chunk in manifest.chunks.sorted(by: { $0.offset < $1.offset }) {
            // Verify chunk checksum
            if configuration.checksumValidation {
                let chunkChecksum = sha256(chunk.data)
                guard chunkChecksum == chunk.checksum else {
                    throw NSError(
                        domain: "DeltaSyncService",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Chunk checksum mismatch at offset \(chunk.offset)"]
                    )
                }
            }
            
            // Apply chunk (replace or insert)
            let endOffset = chunk.offset + chunk.length
            if endOffset <= reconstructed.count {
                // Replace existing data
                reconstructed.replaceSubrange(chunk.offset..<endOffset, with: chunk.data)
            } else if chunk.offset <= reconstructed.count {
                // Partial replacement + append
                reconstructed.replaceSubrange(chunk.offset..<reconstructed.count, with: Data())
                reconstructed.append(chunk.data)
            } else {
                // Append new data
                reconstructed.append(chunk.data)
            }
        }
        
        // Verify reconstructed file checksum
        let reconstructedChecksum = sha256(reconstructed)
        guard reconstructedChecksum == manifest.targetFileChecksum else {
            throw NSError(
                domain: "DeltaSyncService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Reconstructed file checksum mismatch"]
            )
        }
        
        // Write output
        try reconstructed.write(to: outputURL, options: .atomic)
    }
    
    // MARK: - Cloud Sync Integration
    
    /// Syncs a backup to cloud using delta upload
    /// - Parameters:
    ///   - localURL: Local backup file to upload
    ///   - remoteBaseURL: Previous version in cloud (for delta)
    ///   - uploadChunk: Closure to upload individual chunks
    ///   - progress: Progress callback
    /// - Returns: Sync result with statistics
    public func syncToCloud(
        localURL: URL,
        remoteBaseURL: URL?,
        uploadChunk: @escaping (DeltaChunk, Int, Int) async throws -> Void,
        progress: @escaping (Double, String) -> Void
    ) async throws -> SyncResult {
        
        let startTime = Date()
        
        progress(0.0, "Analyzing changes…")
        
        // If no remote base, upload full file
        guard let remoteBaseURL = remoteBaseURL else {
            return try await uploadFullFile(
                localURL: localURL,
                uploadChunk: uploadChunk,
                progress: progress,
                startTime: startTime
            )
        }
        
        // Generate delta
        progress(0.2, "Generating delta…")
        let manifest = try await generateDelta(from: remoteBaseURL, to: localURL)
        
        // If delta is larger than threshold, upload full file
        if manifest.compressionRatio > 0.8 {  // Delta is >80% of original size
            progress(0.3, "Delta too large, uploading full file…")
            return try await uploadFullFile(
                localURL: localURL,
                uploadChunk: uploadChunk,
                progress: progress,
                startTime: startTime
            )
        }
        
        // Upload delta chunks
        progress(0.4, "Uploading \(manifest.chunks.count) changed chunks…")
        
        let totalChunks = manifest.chunks.count
        var uploadedChunks = 0
        var bytesUploaded = 0
        
        for (index, chunk) in manifest.chunks.enumerated() {
            try await uploadChunk(chunk, index, totalChunks)
            uploadedChunks += 1
            bytesUploaded += chunk.data.count
            
            let uploadProgress = 0.4 + (Double(uploadedChunks) / Double(totalChunks)) * 0.6
            progress(
                uploadProgress,
                "Uploaded \(uploadedChunks)/\(totalChunks) chunks (\(formatBytes(bytesUploaded)))"
            )
        }
        
        progress(1.0, "Sync complete")
        
        let duration = Date().timeIntervalSince(startTime)
        
        return SyncResult(
            manifest: manifest,
            uploadedChunks: uploadedChunks,
            totalChunks: totalChunks,
            bytesUploaded: bytesUploaded,
            bytesSaved: manifest.savedBytes,
            duration: duration
        )
    }
    
    // MARK: - Private Helpers
    
    private func generateDeltaChunks(base: Data, target: Data) throws -> [DeltaChunk] {
        var chunks: [DeltaChunk] = []
        let chunkSize = configuration.chunkSize
        
        // Simple block-based diff (in production, use more sophisticated algorithm like rsync)
        var offset = 0
        
        while offset < max(base.count, target.count) {
            let baseChunkEnd = min(offset + chunkSize, base.count)
            let targetChunkEnd = min(offset + chunkSize, target.count)
            
            let baseChunk = base.subdata(in: offset..<baseChunkEnd)
            let targetChunk = target.subdata(in: offset..<targetChunkEnd)
            
            // If chunks differ, create delta chunk
            if baseChunk != targetChunk || targetChunkEnd > base.count {
                let chunkData = targetChunk
                let checksum = sha256(chunkData)
                
                chunks.append(DeltaChunk(
                    offset: offset,
                    length: targetChunk.count,
                    data: chunkData,
                    checksum: checksum
                ))
            }
            
            offset += chunkSize
        }
        
        return chunks
    }
    
    private func uploadFullFile(
        localURL: URL,
        uploadChunk: @escaping (DeltaChunk, Int, Int) async throws -> Void,
        progress: @escaping (Double, String) -> Void,
        startTime: Date
    ) async throws -> SyncResult {
        
        let data = try Data(contentsOf: localURL)
        let checksum = sha256(data)
        
        // Split into chunks for upload
        var chunks: [DeltaChunk] = []
        var offset = 0
        
        while offset < data.count {
            let chunkEnd = min(offset + configuration.chunkSize, data.count)
            let chunkData = data.subdata(in: offset..<chunkEnd)
            let chunkChecksum = sha256(chunkData)
            
            chunks.append(DeltaChunk(
                offset: offset,
                length: chunkData.count,
                data: chunkData,
                checksum: chunkChecksum
            ))
            
            offset += configuration.chunkSize
        }
        
        // Upload all chunks
        var uploadedChunks = 0
        var bytesUploaded = 0
        
        for (index, chunk) in chunks.enumerated() {
            try await uploadChunk(chunk, index, chunks.count)
            uploadedChunks += 1
            bytesUploaded += chunk.data.count
            
            let uploadProgress = 0.3 + (Double(uploadedChunks) / Double(chunks.count)) * 0.7
            progress(uploadProgress, "Uploaded \(uploadedChunks)/\(chunks.count) chunks")
        }
        
        let manifest = DeltaManifest(
            baseFileChecksum: "",
            targetFileChecksum: checksum,
            chunks: chunks,
            totalOriginalSize: data.count,
            totalDeltaSize: data.count,
            compressionRatio: 1.0,
            createdAt: Date()
        )
        
        return SyncResult(
            manifest: manifest,
            uploadedChunks: uploadedChunks,
            totalChunks: chunks.count,
            bytesUploaded: bytesUploaded,
            bytesSaved: 0,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    private func sha256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Cloud Storage Integration

extension CloudBackupService {
    
    /// Uploads backup using delta sync if previous version exists
    public func uploadBackupWithDeltaSync(
        localURL: URL,
        to cloudURL: URL,
        previousVersion: URL? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> DeltaSyncService.SyncResult {
        
        let deltaService = DeltaSyncService()
        
        // Find previous cloud backup if not specified
        let previousBackup: URL?
        if let prev = previousVersion {
            previousBackup = prev
        } else {
            previousBackup = try await findMostRecentBackup(excluding: cloudURL.lastPathComponent)
        }
        
        return try await deltaService.syncToCloud(
            localURL: localURL,
            remoteBaseURL: previousBackup,
            uploadChunk: { chunk, index, total in
                // Upload chunk to cloud storage
                try await self.uploadChunk(chunk, to: cloudURL, chunkIndex: index)
            },
            progress: progress
        )
    }
    
    private func uploadChunk(_ chunk: DeltaSyncService.DeltaChunk, to url: URL, chunkIndex: Int) async throws {
        // Implementation would depend on your cloud storage provider
        // For iCloud, this would use CloudKit or URLSession
        // For now, placeholder implementation
        
        let chunkURL = url.appendingPathExtension("chunk.\(chunkIndex)")
        try chunk.data.write(to: chunkURL)
    }
    
    private func findMostRecentBackup(excluding filename: String) async throws -> URL? {
        let backups = try await listCloudBackups()
        return backups
            .filter { $0.fileName != filename }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .first?
            .fileURL
    }
}
