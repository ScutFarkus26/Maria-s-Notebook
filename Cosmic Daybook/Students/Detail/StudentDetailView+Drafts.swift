// StudentDetailView+Drafts.swift
// How the edit form's date pickers turn into what Save writes.

import Foundation

extension StudentDetailView {
    /// What a date picker's value saves as: nil (leave the stored value as it
    /// is) while it still shows the stand-in it was given for a missing date.
    static func editedDate(_ draft: Date, placeholder: Date?) -> Date? {
        draft == placeholder ? nil : draft
    }
}
