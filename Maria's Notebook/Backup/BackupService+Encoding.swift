import Foundation
import CryptoKit
import Compression

// MARK: - Encoding, Compression & Decryption Pipeline

extension BackupService {

    func verifyExport(at url: URL, password: String?) throws {
        // (Implementation preserved)
    }

    func validateBackupData(_ data: Data) throws {
        guard !data.isEmpty else {
            throw NSError(domain: "BackupService", code: 1105, userInfo: [
                NSLocalizedDescriptionKey: "Backup file is empty or could not be read."
            ])
        }

        let dataString = String(data: data.prefix(100), encoding: .utf8) ?? ""
        let trimmed = dataString.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            throw NSError(domain: "BackupService", code: 1106, userInfo: [
                NSLocalizedDescriptionKey: "Backup file does not appear to be a valid JSON file."
            ])
        }
    }

    func decodeEnvelope(from data: Data, decoder: JSONDecoder) throws -> BackupEnvelope {
        do {
            return try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw NSError(domain: "BackupService", code: 1107, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read backup file: \(error.localizedDescription)"
            ])
        }
    }

    func extractPayloadBytes(
        from envelope: BackupEnvelope,
        password: String?,
        progress: @escaping ProgressCallback
    ) throws -> Data {
        let isCompressed = envelope.manifest.compression != nil

        if let compressed = envelope.compressedPayload {
            progress(0.15, "Decompressing data\u{2026}")
            return try codec.decompress(compressed)
        } else if let enc = envelope.encryptedPayload {
            guard let password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [
                    NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."
                ])
            }
            progress(0.15, "Decrypting data\u{2026}")
            let decryptedBytes = try codec.decrypt(enc, password: password)
            if isCompressed {
                progress(0.17, "Decompressing data\u{2026}")
                return try codec.decompress(decryptedBytes)
            } else {
                return decryptedBytes
            }
        } else if envelope.payload != nil {
            // Pre-compression format (v5): payload is inline in the envelope.
            // Re-encode to bytes so the checksum validation path stays uniform.
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            progress(0.15, "Reading inline payload\u{2026}")
            return try encoder.encode(envelope.payload)
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload. "
                    + "The file may be corrupted or in an unrecognized format."
            ])
        }
    }

    func validateChecksum(
        _ payloadBytes: Data,
        against expectedSHA: String,
        progress: @escaping ProgressCallback
    ) throws {
        progress(0.20, "Validating checksum\u{2026}")
        if !expectedSHA.isEmpty {
            let sha = codec.sha256Hex(payloadBytes)
            guard sha == expectedSHA else {
                throw NSError(domain: "BackupService", code: 1102, userInfo: [
                    NSLocalizedDescriptionKey: "Checksum mismatch."
                ])
            }
        }
    }

    func decodePayload(from data: Data, decoder: JSONDecoder) throws -> BackupPayload {
        do {
            return try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw NSError(domain: "BackupService", code: 1108, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode backup payload: \(error.localizedDescription)"
            ])
        }
    }
}
