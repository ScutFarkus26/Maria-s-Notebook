// BackupSharingService.swift
// Handles secure backup sharing functionality

import Foundation
#if os(macOS)
import AppKit
#endif

/// Service for sharing backups securely.
/// Provides functionality to prepare backups for sharing via AirDrop, email, or other methods.
@MainActor
public final class BackupSharingService {

    // MARK: - Types

    public enum SharingError: LocalizedError {
        case fileNotFound
        case preparationFailed(Error)
        case sharingCancelled
        case unsupportedPlatform

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The backup file could not be found."
            case .preparationFailed(let error):
                return "Failed to prepare backup for sharing: \(error.localizedDescription)"
            case .sharingCancelled:
                return "Sharing was cancelled."
            case .unsupportedPlatform:
                return "Sharing is not supported on this platform."
            }
        }
    }

    /// Options for sharing a backup
    public struct SharingOptions: Sendable {
        public var includeMetadata: Bool
        public var encryptIfUnencrypted: Bool
        public var password: String?
        public var createTemporaryCopy: Bool

        public nonisolated static var `default`: SharingOptions {
            SharingOptions(
                includeMetadata: true,
                encryptIfUnencrypted: false,
                password: nil,
                createTemporaryCopy: true
            )
        }

        public nonisolated init(
            includeMetadata: Bool = true,
            encryptIfUnencrypted: Bool = false,
            password: String? = nil,
            createTemporaryCopy: Bool = true
        ) {
            self.includeMetadata = includeMetadata
            self.encryptIfUnencrypted = encryptIfUnencrypted
            self.password = password
            self.createTemporaryCopy = createTemporaryCopy
        }
    }

    /// Information about a prepared share
    public struct PreparedShare {
        public let url: URL
        public let fileName: String
        public let fileSize: Int64
        public let isEncrypted: Bool
        public let isTemporary: Bool
        public let expiresAt: Date?

        public var formattedFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
    }

    // MARK: - Properties

    private let backupService: BackupService
    private let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    /// Directory for temporary share files
    private var shareDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupShares")
    }

    // MARK: - Public API

    /// Prepares a backup file for sharing.
    /// If encryption is requested and the backup is not encrypted, creates an encrypted copy.
    ///
    /// - Parameters:
    ///   - backupURL: URL of the backup to share
    ///   - options: Sharing options
    /// - Returns: Prepared share with URL to share
    public func prepareForSharing(
        backupURL: URL,
        options: SharingOptions = SharingOptions.default
    ) async throws -> PreparedShare {
        let access = backupURL.startAccessingSecurityScopedResource()
        defer { if access { backupURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw SharingError.fileNotFound
        }

        // Read the backup to check if encrypted
        let data = try Data(contentsOf: backupURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        let isCurrentlyEncrypted = envelope.encryptedPayload != nil

        // Determine if we need to create a modified copy
        let needsEncryption = options.encryptIfUnencrypted && !isCurrentlyEncrypted && options.password != nil
        let needsCopy = options.createTemporaryCopy || needsEncryption

        if needsCopy {
            // Ensure share directory exists
            try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)

            // Create share filename
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let timestamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let shareFilename = "Share-\(timestamp).\(BackupFile.fileExtension)"
            let shareURL = shareDirectory.appendingPathComponent(shareFilename)

            if needsEncryption, let password = options.password {
                // Re-encrypt the backup with the provided password
                try await createEncryptedCopy(
                    from: backupURL,
                    to: shareURL,
                    password: password,
                    envelope: envelope
                )
            } else {
                // Just copy the file
                try FileManager.default.copyItem(at: backupURL, to: shareURL)
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: shareURL.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0

            return PreparedShare(
                url: shareURL,
                fileName: shareFilename,
                fileSize: fileSize,
                isEncrypted: isCurrentlyEncrypted || needsEncryption,
                isTemporary: true,
                expiresAt: Date().addingTimeInterval(3600) // 1 hour expiry
            )
        } else {
            // Share the original file
            let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0

            return PreparedShare(
                url: backupURL,
                fileName: backupURL.lastPathComponent,
                fileSize: fileSize,
                isEncrypted: isCurrentlyEncrypted,
                isTemporary: false,
                expiresAt: nil
            )
        }
    }

    /// Presents the system share sheet for a backup.
    ///
    /// - Parameters:
    ///   - preparedShare: The prepared share to present
    ///   - view: The view to anchor the share sheet to (optional)
    #if os(macOS)
    public func presentShareSheet(
        for preparedShare: PreparedShare,
        relativeTo view: NSView? = nil
    ) {
        let picker = NSSharingServicePicker(items: [preparedShare.url])

        if let view = view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let window = NSApp.mainWindow,
                  let contentView = window.contentView {
            let centerPoint = NSRect(
                x: contentView.bounds.midX - 100,
                y: contentView.bounds.midY,
                width: 200,
                height: 1
            )
            picker.show(relativeTo: centerPoint, of: contentView, preferredEdge: .minY)
        }
    }
    #endif

    /// Copies the backup file to the clipboard (macOS only).
    ///
    /// - Parameter preparedShare: The prepared share to copy
    #if os(macOS)
    public func copyToClipboard(_ preparedShare: PreparedShare) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([preparedShare.url as NSURL])
    }
    #endif

    /// Cleans up temporary share files.
    public func cleanupTemporaryFiles() {
        guard FileManager.default.fileExists(atPath: shareDirectory.path) else { return }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: shareDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []

        let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour ago

        for file in files {
            if let creationDate = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               creationDate < cutoffDate {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Lists all available sharing services for a backup.
    #if os(macOS)
    @available(macOS, deprecated: 13.0, message: "Use NSSharingServicePicker.standardShareMenuItem instead")
    public func availableSharingServices(for url: URL) -> [NSSharingService] {
        NSSharingService.sharingServices(forItems: [url])
    }
    #endif

    // MARK: - Private Helpers

    private func createEncryptedCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        password: String,
        envelope: BackupEnvelope
    ) async throws {
        // Get the payload bytes
        let payloadBytes: Data

        if let payload = envelope.payload {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            payloadBytes = try encoder.encode(payload)
        } else if let compressed = envelope.compressedPayload {
            // Already compressed, just need to encrypt
            let encryptedData = try codec.encrypt(compressed, password: password)

            // Create new envelope with encrypted payload
            let newEnvelope = BackupEnvelope(
                formatVersion: envelope.formatVersion,
                createdAt: envelope.createdAt,
                appBuild: envelope.appBuild,
                appVersion: envelope.appVersion,
                device: envelope.device,
                manifest: envelope.manifest,
                payload: nil,
                encryptedPayload: encryptedData,
                compressedPayload: nil
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let envBytes = try encoder.encode(newEnvelope)
            try envBytes.write(to: destinationURL, options: .atomic)
            return
        } else {
            throw SharingError.preparationFailed(NSError(
                domain: "BackupSharingService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot encrypt: backup has no payload"]
            ))
        }

        // Compress and encrypt
        let compressed = try codec.compress(payloadBytes)
        let encrypted = try codec.encrypt(compressed, password: password)

        // Create new envelope
        let newEnvelope = BackupEnvelope(
            formatVersion: envelope.formatVersion,
            createdAt: envelope.createdAt,
            appBuild: envelope.appBuild,
            appVersion: envelope.appVersion,
            device: envelope.device,
            manifest: BackupManifest(
                entityCounts: envelope.manifest.entityCounts,
                sha256: codec.sha256Hex(payloadBytes),
                notes: envelope.manifest.notes,
                compression: BackupFile.compressionAlgorithm
            ),
            payload: nil,
            encryptedPayload: encrypted,
            compressedPayload: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let envBytes = try encoder.encode(newEnvelope)
        try envBytes.write(to: destinationURL, options: .atomic)

        // Set restrictive permissions
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: destinationURL.path
        )
    }
}
