// BackupCodec.swift
// Handles compression and encryption/decryption for backup data

import Foundation
import CryptoKit
import Compression

/// Handles compression and encryption for backup operations
struct BackupCodec {

    // MARK: - Compression

    /// Compresses data using LZFSE compression algorithm
    func compress(_ data: Data) throws -> Data {
        let bufferSize = data.count + (data.count / 10) + 64
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        return try data.withUnsafeBytes { sourceRawBuffer in
            guard let sourceBuffer = sourceRawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw NSError(domain: "BackupCodec", code: 1200, userInfo: [NSLocalizedDescriptionKey: "Compression failed: could not access source memory"])
            }
            let compressedSize = compression_encode_buffer(destinationBuffer, bufferSize, sourceBuffer, data.count, nil, COMPRESSION_LZFSE)
            guard compressedSize > 0 else {
                throw NSError(domain: "BackupCodec", code: 1200, userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
            }
            return Data(bytes: destinationBuffer, count: compressedSize)
        }
    }

    /// Decompresses data using LZFSE decompression algorithm
    func decompress(_ data: Data) throws -> Data {
        var bufferSize = data.count * 4
        let maxAttempts = 3
        var attempt = 0
        return try data.withUnsafeBytes { sourceRawBuffer in
            guard let sourceBuffer = sourceRawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw NSError(domain: "BackupCodec", code: 1201, userInfo: [NSLocalizedDescriptionKey: "Decompression failed: could not access source memory"])
            }
            while attempt < maxAttempts {
                let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { destinationBuffer.deallocate() }
                let decompressedSize = compression_decode_buffer(destinationBuffer, bufferSize, sourceBuffer, data.count, nil, COMPRESSION_LZFSE)
                if decompressedSize > 0 && decompressedSize < bufferSize {
                    return Data(bytes: destinationBuffer, count: decompressedSize)
                }
                bufferSize *= 2
                attempt += 1
            }
            throw NSError(domain: "BackupCodec", code: 1201, userInfo: [NSLocalizedDescriptionKey: "Decompression failed: buffer size insufficient"])
        }
    }

    // MARK: - Encryption

    /// Encrypts data using AES-GCM with password-based key derivation
    /// - Parameters:
    ///   - data: Data to encrypt (typically already compressed)
    ///   - password: Password for encryption
    /// - Returns: Encrypted data with salt prepended
    func encrypt(_ data: Data, password: String) throws -> Data {
        let saltKey = SymmetricKey(size: .bits256)
        let salt = saltKey.withUnsafeBytes { Data($0) }

        let key = deriveKey(password: password, salt: salt)

        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "BackupCodec", code: 1100, userInfo: [NSLocalizedDescriptionKey: "Encryption failed (could not combine data)."])
        }

        // Prepend salt to encrypted data
        return salt + combined
    }

    /// Decrypts data using AES-GCM with password-based key derivation
    /// - Parameters:
    ///   - data: Encrypted data with salt prepended
    ///   - password: Password for decryption
    /// - Returns: Decrypted data
    func decrypt(_ data: Data, password: String) throws -> Data {
        // Extract salt (first 32 bytes)
        guard data.count > 32 else {
            throw NSError(domain: "BackupCodec", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Decryption failed: data too short to contain salt"])
        }

        let salt = data.prefix(32)
        let encryptedData = data.dropFirst(32)

        let key = deriveKey(password: password, salt: salt)

        guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData) else {
            throw NSError(domain: "BackupCodec", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Decryption failed: invalid sealed box"])
        }

        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Helpers

    /// Derives an encryption key from a password and salt using HKDF-SHA256
    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: password.data(using: .utf8)!)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKey, salt: salt, outputByteCount: 32)
    }

    /// Computes SHA256 hash and returns as hex string
    func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
