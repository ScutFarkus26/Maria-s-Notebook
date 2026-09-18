//
//  JSONValue+Schema.swift
//  Cosmic Daybook
//
//  Schema trimming for the tool catalogue. A batch tool repeats its single
//  form's fields inside an array item; the model reads the descriptions once
//  at the top level, so the copy inside `items` carries types and constraints
//  only. Every tool definition is sent on every connection, so bytes here are
//  paid on every conversation.
//

import Foundation

extension JSONValue {
    /// The same schema with every `description` key removed, at every depth.
    var withoutDescriptions: JSONValue {
        switch self {
        case .object(let fields):
            var trimmed: [String: JSONValue] = [:]
            for (key, value) in fields where key != "description" {
                trimmed[key] = value.withoutDescriptions
            }
            return .object(trimmed)
        case .array(let items):
            return .array(items.map(\.withoutDescriptions))
        default:
            return self
        }
    }
}
