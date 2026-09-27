// BackupImporter+EntityDecoders.swift
// Which DTO type each archive entity's rows decode to, and where they go.

import Foundation

extension BackupImporter {

    /// How one entity's NDJSON rows are read: each row decoded, in order, with
    /// that entity's DTO type, and then either all kept in the entity's
    /// `BackupPayload` field (`assign`, the restore) or handed over one at a
    /// time and dropped (`visit`, the preview). Both stop at the first row
    /// that does not decode and throw its error, so a restore and a preview
    /// skip exactly the same entries.
    nonisolated struct EntityDecoder: Sendable {
        let assign: @Sendable (inout BackupPayload, [Data], JSONDecoder) throws -> Void
        let visit: @Sendable ([Data], JSONDecoder, (any Sendable) -> Void) throws -> Void
    }

    private nonisolated static func decodeAll<T: Decodable>(
        _ type: T.Type,
        _ lines: [Data],
        _ decoder: JSONDecoder
    ) throws -> [T] {
        try lines.map { try decoder.decode(T.self, from: $0) }
    }

    private nonisolated static func visitAll<T: Decodable & Sendable>(
        _ type: T.Type,
        _ lines: [Data],
        _ decoder: JSONDecoder,
        _ visit: (any Sendable) -> Void
    ) throws {
        for line in lines {
            visit(try decoder.decode(T.self, from: line))
        }
    }

    /// A row for one of the payload's always-present arrays.
    nonisolated static func rows<T: Decodable & Sendable>(
        _ type: T.Type,
        _ field: WritableKeyPath<BackupPayload, [T]> & Sendable
    ) -> EntityDecoder {
        EntityDecoder(
            assign: { payload, lines, decoder in payload[keyPath: field] = try decodeAll(T.self, lines, decoder) },
            visit: { lines, decoder, visit in try visitAll(T.self, lines, decoder, visit) }
        )
    }

    /// A row for one of the payload's later-format (optional) arrays.
    nonisolated static func optionalRows<T: Decodable & Sendable>(
        _ type: T.Type,
        _ field: WritableKeyPath<BackupPayload, [T]?> & Sendable
    ) -> EntityDecoder {
        EntityDecoder(
            assign: { payload, lines, decoder in payload[keyPath: field] = try decodeAll(T.self, lines, decoder) },
            visit: { lines, decoder, visit in try visitAll(T.self, lines, decoder, visit) }
        )
    }

    /// Entity name → how its rows decode, from `BackupEntityTable`.
    nonisolated static let entityDecoders: [String: EntityDecoder] = Dictionary(
        uniqueKeysWithValues: BackupEntityTable.entities.map { ($0.name, $0.decoder) }
    )
}
