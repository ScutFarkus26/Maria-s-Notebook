//
//  Dictionary+InsertIfAbsent.swift
//  Maria's Notebook
//
//  Created by Refactoring on 2/8/26.
//

import Foundation

extension Dictionary {
    /// Inserts a value for the given key only if the key doesn't already exist in the dictionary.
    /// This is a more expressive alternative to: `if dict[key] == nil { dict[key] = value }`
    ///
    /// - Parameters:
    ///   - value: The value to insert
    ///   - key: The key for the value
    mutating func insertIfAbsent(_ value: Value, forKey key: Key) {
        if self[key] == nil {
            self[key] = value
        }
    }
}
