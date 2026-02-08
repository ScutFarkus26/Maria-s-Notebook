//
//  StudentSortComparator.swift
//  Maria's Notebook
//
//  Created by Refactoring on 2/8/26.
//

import Foundation

/// Provides consistent student sorting logic across the application.
enum StudentSortComparator {
    /// Sorts students by first name, then last name (both case-insensitive).
    static func byFirstName(_ lhs: Student, _ rhs: Student) -> Bool {
        let firstNameComparison = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
        if firstNameComparison == .orderedSame {
            return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
        }
        return firstNameComparison == .orderedAscending
    }
    
    /// Sorts students by last name, then first name (both case-insensitive).
    static func byLastName(_ lhs: Student, _ rhs: Student) -> Bool {
        let lastNameComparison = lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName)
        if lastNameComparison == .orderedSame {
            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        }
        return lastNameComparison == .orderedAscending
    }
}
