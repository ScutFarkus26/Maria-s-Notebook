//
//  CDStudent+CloudKitID.swift
//  Maria's Notebook
//
//  Created by Refactoring on 2/8/26.
//

import Foundation

extension CDStudent {
    /// Returns the student's ID as a string for CloudKit compatibility.
    /// Use this instead of manually calling `.id.uuidString` throughout the codebase.
    var cloudKitKey: String {
        id?.uuidString ?? ""
    }
}
