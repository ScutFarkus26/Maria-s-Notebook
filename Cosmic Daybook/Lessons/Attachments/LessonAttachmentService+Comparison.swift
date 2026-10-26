//
//  LessonAttachmentService+Comparison.swift
//  Cosmic Daybook
//
//  Whether a replace's new file is the one already attached, byte for byte.
//

import Foundation

extension LessonAttachmentService {
    /// Whether the stored file at `relativePath` has the same bytes as the
    /// file at `url`. False when the stored file isn't on this device and
    /// doesn't come down within `comparisonTimeout`.
    func hasSameBytes(relativePath: String, as url: URL) async -> Bool {
        guard !relativePath.trimmed().isEmpty,
              let stored = try? storage.resolve(relativePath: relativePath),
              let local = await UbiquitousFile.ensureLocal(stored, timeout: Self.comparisonTimeout) else {
            return false
        }
        return await Self.sameContents(local, url)
    }

    /// Two regular files of the same size with the same bytes, read a
    /// megabyte at a time off the main actor.
    @concurrent
    nonisolated static func sameContents(_ lhs: URL, _ rhs: URL) async -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let left = try? lhs.resourceValues(forKeys: keys),
              let right = try? rhs.resourceValues(forKeys: keys),
              left.isRegularFile == true, right.isRegularFile == true,
              left.fileSize == right.fileSize,
              let leftHandle = try? FileHandle(forReadingFrom: lhs),
              let rightHandle = try? FileHandle(forReadingFrom: rhs) else { return false }
        defer {
            try? leftHandle.close()
            try? rightHandle.close()
        }
        do {
            while true {
                let leftChunk = try leftHandle.read(upToCount: 1 << 20) ?? Data()
                let rightChunk = try rightHandle.read(upToCount: 1 << 20) ?? Data()
                guard leftChunk == rightChunk else { return false }
                if leftChunk.isEmpty { return true }
            }
        } catch {
            return false
        }
    }
}
