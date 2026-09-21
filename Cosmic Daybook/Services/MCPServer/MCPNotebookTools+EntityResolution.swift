//
//  MCPNotebookTools+EntityResolution.swift
//  Cosmic Daybook
//
//  One fetch-by-id for the tool families whose write tools take a bare
//  `<thing>_id` string: parse the UUID, look the row up, and fail with the
//  wording the tool already used. The per-family `resolveX` helpers stay —
//  they name the argument and the noun and forward here.
//
//  Resolvers that match on more than an id (a student by name, a lesson by
//  title, a track by area) are not this shape and live with their tools.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// Looks up the `type` row whose `id` equals `reference`.
    ///
    /// - Parameters:
    ///   - argument: the tool argument the reference came from, for the parse error.
    ///   - noun: how the tool names the thing, for the not-found error.
    /// - Throws: `MCPToolError` when `reference` is not a UUID or no row has that id.
    static func resolveEntity<T: NSManagedObject>(
        _ type: T.Type,
        reference: String,
        argument: String,
        noun: String,
        in modelContext: NSManagedObjectContext
    ) throws -> T {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("\(argument) must be a uuid, got \"\(reference)\".")
        }
        guard let object = modelContext.object(type, id: id) else {
            throw MCPToolError("No \(noun) with id \(reference) was found.")
        }
        return object
    }
}
